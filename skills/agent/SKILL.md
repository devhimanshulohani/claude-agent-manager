---
description: Spawn and manage autonomous background agents
argument-hint: "task description" | list | switch <id> | stop <id> | history | clean | merge <id>
allowed-tools: Agent, Bash, Read, Edit, Write, Glob, Grep, TaskOutput, TaskStop, TaskCreate, TaskUpdate, TaskList
---

# Agent Manager v2

Parse `$ARGUMENTS` and execute the matching command below. Persistent state lives in `.claude/agents/registry.json` (source of truth). Task system is for live monitoring only.

**Registry:** Read `.claude/agents/registry.json` — if missing/corrupt, default to `{ "version": 1, "agents": [] }`. Always `mkdir -p .claude/agents` before writing.
**Agent ID:** Generate via `date +%s | shasum | head -c 6` (6-char hex).
**Age format:** `<N>m ago` / `<N>h ago` / `<N>d ago` relative to `createdAt`.

## `list`

1. Read registry. If empty, say "No agents found. Spawn one with: `/agent "your task"`"
2. For each agent with status `running`:
   - Try `TaskOutput` with `block: false, timeout: 3000` using stored `taskId`
   - If task found & completed → check `.claude/agents/<id>-result.txt`, parse it, update entry to `completed` with branch/commit/files/completedAt
   - If task NOT found (new session) → check result file. If exists, parse & mark `completed`. If not, check `git branch --list <branch>` — branch exists → `unknown`, no branch → `failed`
3. Write updated registry. Display table: **ID | Status | Description | Branch | Age**

## `switch <id>`

1. Look up agent by ID in registry (prefix match if unambiguous). If not found, show available IDs.
2. If `running` with live taskId → `TaskOutput` with `block: false, timeout: 5000`
3. Otherwise → read `.claude/agents/<id>-result.txt` for summary
4. Show: status, description, branch, and suggest `git diff main...<branch>` and `/agent merge <id>`

## `stop <id>`

1. Look up agent in registry. If not found, say so.
2. Try `TaskStop` with `task_id` (ignore errors if gone)
3. Update registry: status → `stopped`, set `completedAt`. Write registry. Confirm.

## `history`

1. Read registry. If empty, say "No agent history found"
2. Display ALL agents sorted by `createdAt` desc. Table: **ID | Status | Description | Branch | Commit Message | Date**

## `clean`

1. Read registry. Filter agents with status `completed`/`stopped`/`merged`/`failed`/`unknown`
2. For each: remove worktree (`git worktree remove <path> --force`), delete `<id>-result.txt`, delete branch if `merged` (`git branch -d <branch>`). Ignore errors.
3. Remove entries from registry, write it. Report: "Cleaned up N agent(s). M still running."

## `merge <id>`

1. Look up agent. If not found or status not `completed`/`unknown`, reject with reason.
2. Verify branch exists (`git branch --list <branch>`). If not, say so.
3. Run `git merge <branch>`. On success → update status to `merged`, write registry, suggest `/agent clean`. On conflict → tell user, suggest `git merge --abort`.

## Spawn (default — no command match)

1. Generate ID, read registry
2. `TaskCreate` with subject (60 chars max), description, activeForm (present continuous)
3. Add entry to registry: `{ id, taskId: null, description, status: "running", branch: null, worktreePath: null, commit: null, commitMessage: null, createdAt: <ISO now>, completedAt: null, filesChanged: [] }`. Write registry.
4. Spawn `Agent` with `subagent_type: "general-purpose"`, `run_in_background: true`, `isolation: "worktree"`, prompt:

```
You are an autonomous agent. **Task:** {description} | **Agent ID:** {id}

Instructions:
1. Work autonomously — no questions, make reasonable decisions
2. Read and understand relevant code before changing it
3. Make all changes needed, then verify: TypeScript → `npm run build`, Rust → `cd src-tauri && cargo check`
4. Commit with conventional format: `type(scope): subject`
5. CRITICAL — after committing, write result file to the ORIGINAL repo (not worktree):

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
FILES=$(git diff --name-only HEAD~1 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
mkdir -p {repo_absolute_path}/.claude/agents
cat > {repo_absolute_path}/.claude/agents/{id}-result.txt << RESULT_EOF
branch: $BRANCH
commit: $COMMIT
commitMessage: $COMMIT_MSG
filesChanged: $FILES
summary: Completed task — {short description}
RESULT_EOF

You are in an isolated worktree. Make changes freely.
```

5. Update registry entry's `taskId` from TaskCreate. Write registry.
6. Tell user: agent `<id>` spawned. Commands: `/agent list`, `/agent switch <id>`, `/agent stop <id>`, `/agent merge <id>`
