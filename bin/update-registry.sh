#!/usr/bin/env bash
# update-registry.sh — Called by SubagentStop hook when a worker agent finishes.
# Uses node (always available in Claude Code) for reliable JSON parsing.
# Includes file locking to prevent race conditions with concurrent agents.

set -euo pipefail

INPUT=$(cat)

# node is always available since Claude Code runs on Node.js
command -v node >/dev/null 2>&1 || exit 0

node -e '
const fs = require("fs");
const path = require("path");

const input = JSON.parse(process.argv[1]);
const agentId = input.agent_id;
const cwd = input.cwd;

if (!cwd || !agentId) process.exit(0);

const registryPath = path.join(cwd, ".claude", "agents", "registry.json");
if (!fs.existsSync(registryPath)) process.exit(0);

const lockDir = path.join(cwd, ".claude", "agents", ".lock");

// Acquire lock (mkdir is atomic on all OSes)
let locked = false;
for (let i = 0; i < 50; i++) {
  try { fs.mkdirSync(lockDir); locked = true; break; } catch (e) {
    if (e.code !== "EEXIST") process.exit(0);
    // Wait 100ms and retry
    const start = Date.now(); while (Date.now() - start < 100) {}
  }
}
if (!locked) process.exit(0);

try {
  const registry = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  const agent = registry.agents.find(a => a.taskId === agentId);
  if (!agent) process.exit(0);

  const resultPath = path.join(cwd, ".claude", "agents", agent.id + "-result.txt");
  const now = new Date().toISOString();

  if (fs.existsSync(resultPath)) {
    const content = fs.readFileSync(resultPath, "utf8");
    const get = (key) => {
      const m = content.match(new RegExp("^" + key + ":\\s*(.*)$", "m"));
      return m ? m[1].trim() : null;
    };
    agent.status = "completed";
    agent.branch = get("branch") || agent.branch;
    agent.commit = get("commit") || agent.commit;
    agent.commitMessage = get("commitMessage") || agent.commitMessage;
    const files = get("filesChanged");
    agent.filesChanged = files ? files.split(",").map(f => f.trim()).filter(Boolean) : agent.filesChanged;
    agent.completedAt = now;
  } else {
    agent.status = "completed";
    agent.completedAt = now;
  }

  // Atomic write: tmp then rename
  const tmpPath = registryPath + ".tmp";
  fs.writeFileSync(tmpPath, JSON.stringify(registry, null, 2) + "\n");
  fs.renameSync(tmpPath, registryPath);
} finally {
  // Release lock
  try { fs.rmdirSync(lockDir); } catch (e) {}
}
' "$INPUT"

exit 0
