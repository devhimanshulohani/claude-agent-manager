---
name: agent
description: Spawn and manage autonomous background agents with persistent state across sessions
argument-hint: '"task" | list | switch <id> | stop <id> | merge <id> | resume <id> | retry <id> | diff <id> | logs <id> | batch | note <id> | watch <id> | rebase <id> | export <id> | stats | history | clean'
disable-model-invocation: true
effort: high
allowed-tools: Agent, AskUserQuestion, Bash, Read, Edit, Write, Glob, Grep, TaskOutput, TaskStop, TaskCreate, TaskUpdate, TaskList
---

# Agent Manager v4

Parse `$ARGUMENTS` and execute the matching command below. Persistent state lives in `.claude/agents/registry.json` (source of truth). Task system is for live monitoring only.

**Pre-flight:** Before executing any command, verify the current directory is inside a git repository (`git rev-parse --is-inside-work-tree`). If not, reject: "Agent manager requires a git repository. Run `git init` first."
**Registry:** Read `.claude/agents/registry.json` — if missing/corrupt, default to `{ "version": 2, "defaultBranch": null, "agents": [] }`. If version is 1 or missing, migrate: add `model: null, effort: null, color: null, maxTurns: null` to each agent entry, add `defaultBranch: null` at top level, set version to 2, write immediately. Always `mkdir -p .claude/agents` before writing.
**Atomic writes:** Always write registry to `.claude/agents/registry.json.tmp` first, then rename to `.claude/agents/registry.json`. This prevents corruption from interrupted writes.
**Default branch:** Read from `registry.defaultBranch`. If null (first time using the plugin in this repo), ask the user using AskUserQuestion: "What is your default/base branch? (e.g., main, master, develop)". Store the answer in `registry.defaultBranch` and write registry. Once set, never ask again. Use `{defaultBranch}` everywhere in this document instead of a hardcoded branch name.
**Agent ID:** Generate via `echo "$(date +%s)$$.$RANDOM" | shasum | head -c 6` (6-char hex). `$$` (PID) + `$RANDOM` ensures uniqueness even when called multiple times in the same second (e.g., `batch`).
**Age format:** `<N>m ago` / `<N>h ago` / `<N>d ago` relative to `createdAt`.
**Prefix match:** All ID-based commands support prefix matching. If the prefix is ambiguous (matches multiple agents), reject and show the matching IDs. If no match, show all available IDs.
**Templates dir:** `.claude/agents/templates/` — JSON files with required fields `{ name, description }` and optional `{ verifyCommand, commitFormat }`. `verifyCommand` overrides Phase 4 auto-detection; `commitFormat` overrides the default conventional commit format.
**User defaults:** If env var `CLAUDE_PLUGIN_OPTION_DEFAULT_MODEL` is set, use it as default model when `--model` is not specified. If `CLAUDE_PLUGIN_OPTION_DEFAULT_EFFORT` is set, use it as default effort level. These are configured when the user enables the plugin.
**Auto-registry:** A `SubagentStop` hook automatically updates the registry when a worker agent completes. The `list` command still verifies status as a fallback.
**Flag validation:** `--model` must be one of `haiku`, `sonnet`, `opus`. `--color` must be one of `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`. `--effort` must be one of `low`, `medium`, `high`, `max`. `--max-turns` must be a positive integer. Reject invalid values with a clear error message listing valid options.

---

## `list`

1. Read registry. If empty, say "No agents found. Spawn one with: `/agent "your task"`"
2. For each agent with status `running`:
   - If `taskId` is null → mark as `unknown`, continue
   - First, check if `.claude/agents/<id>-result.txt` exists (Read it). If it exists → parse it, update entry to `completed` with branch/commit/files/completedAt. Continue to next agent.
   - If no result file, try `TaskOutput` with `block: false, timeout: 3000` using stored `taskId`
   - If task found & completed → check result file again, update to `completed`
   - If task found & still running → leave status as `running`, continue
   - If task found & errored → mark as `failed`
   - If task NOT found (new session) → if `branch` is null → `unknown`. Otherwise check `git branch --list <branch>` — branch exists → `unknown`, no branch → `failed`
3. Write updated registry. Display table: **ID | Status | Description | Branch | Age**

## `switch <id>`

1. Look up agent by ID in registry (prefix match). If not found, show available IDs.
2. If `running` and `taskId` is not null → first check result file `.claude/agents/<id>-result.txt`. If exists, update to `completed` and show summary. Otherwise try `TaskOutput` with `block: false, timeout: 5000` and display the latest output to the user. If `running` with null `taskId` → say "Agent is running but has no task handle (spawn may have partially failed). Try `/agent list` to refresh or `/agent stop <id>`."
3. Otherwise → read `.claude/agents/<id>-result.txt` for summary. If file missing, say "No result file yet. Agent may still be in progress or failed without output."
4. Show: status, description, branch, model (if set), color (if set). Suggest next actions based on status:
   - `running` → `/agent watch <id>` or `/agent stop <id>`
   - `completed` → `/agent merge <id>`, `/agent diff <id>`
   - `unknown`/`stopped` → `/agent merge <id>`, `/agent diff <id>`, `/agent resume <id>`
   - `failed` → `/agent retry <id>` or `/agent resume <id>`
   - `merged` → `/agent clean`
   - If branch exists (any status), also suggest `git diff {defaultBranch}...<branch>`

## `stop <id>`

1. Look up agent in registry (prefix match). If not found, say so. If status is not `running`, reject: "Agent `<id>` is `<status>`, not running."
2. If `taskId` is not null, try `TaskStop` with `task_id` (ignore errors if gone). If `taskId` is null, skip — just update status.
3. Update registry: status → `stopped`, set `completedAt`. Write registry. Confirm.

## `history`

1. Read registry. If empty, say "No agent history found"
2. Display ALL agents sorted by `createdAt` desc. Table: **ID | Status | Description | Branch | Commit Message | Model | Date**. Show "—" for null/empty fields. Show notes count if agent has notes (e.g., "2 notes").

## `clean`

1. Read registry. Filter agents with status `completed`/`stopped`/`merged`/`failed`/`unknown`
2. For each: delete `.claude/agents/<id>-result.txt` and `.claude/agents/<id>.patch` (if exists), delete branch if `merged` and `branch` is not null (`git branch -d <branch>`). Ignore errors. (Worktrees from `isolation: "worktree"` are auto-managed by Claude Code.)
3. Remove entries from registry, write it. Report: "Cleaned up N agent(s). M still running."

## `merge <id>`

1. Look up agent (prefix match). If not found or status not `completed`/`unknown`/`stopped`, reject with reason.
2. If `branch` is null, reject: "No branch recorded for this agent." Otherwise, verify branch exists (`git branch --list <branch>`). If not, say so.
3. Check working tree is clean (`git status --porcelain`). If dirty, reject: "Working tree has uncommitted changes. Commit or stash first."
4. Run `git checkout {defaultBranch} && git merge <branch>`. On success → update status to `merged`, write registry, suggest `/agent clean`. On conflict → tell user, suggest `git merge --abort`.

---

## `resume <id>`

1. Look up agent in registry (prefix match). Must have status `stopped`/`failed`/`unknown`/`completed`. Reject if `running`/`merged`.
2. If `branch` is null, say "No branch to resume from. Use `/agent retry <id>` to start fresh." Otherwise, verify branch exists (`git branch --list <branch>`). If not, say "Branch no longer exists. Use `/agent retry <id>` to start fresh."
3. Read `.claude/agents/<id>-result.txt` — this contains the completion context (branch, files changed, summary of what was done). If missing, fall back to `git log {defaultBranch}..<branch> --oneline` (1 command only).
4. Update registry: status → `running`, clear `completedAt`. Write registry.
5. `TaskCreate` with subject: `Resume: <original description>` (60 chars max), activeForm (present continuous).
6. Spawn `Agent` with `subagent_type: "agent-manager:worker"`, prompt:

```
You are RESUMING previous work. **Task:** {description} | **Agent ID:** {id}

**Previous work summary:**
{result file contents}

**Resume instructions:**
- Fetch and checkout the existing branch: `git fetch origin {branch} 2>/dev/null; git checkout {branch} 2>/dev/null || git checkout -b {branch} origin/{branch} 2>/dev/null || echo "Warning: branch {branch} not found"`
- Read the changed files and understand what was already completed
- Identify what remains to be done vs what is already done
- Do NOT redo completed work — only pick up where it left off
- Then proceed through the standard phases (Plan, Implement, Verify, Commit)
{if verifyCommand}

**Verify command:** `{verifyCommand}`
{end}
{if commitFormat}

**Commit format:** `{commitFormat}`
{end}

**CRITICAL — after committing, write the result file to the ORIGINAL repo (not worktree):**

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
FILES=$(git diff {defaultBranch}..HEAD --name-only 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
DIFF_STAT=$(git diff {defaultBranch}..HEAD --stat 2>/dev/null | tail -5)
COMMIT_LOG=$(git log {defaultBranch}..HEAD --oneline 2>/dev/null)
mkdir -p {repo_absolute_path}/.claude/agents
cat > {repo_absolute_path}/.claude/agents/{id}-result.txt << RESULT_EOF
branch: $BRANCH
commit: $COMMIT
commitMessage: $COMMIT_MSG
filesChanged: $FILES
summary: Resumed and completed task — {short description}
commitLog: $COMMIT_LOG
diffStat: $DIFF_STAT
RESULT_EOF
```

**Template handling (same as Spawn):** Read `verifyCommand` and `commitFormat` from the registry entry. Include `{if ...}` blocks only when the value is set. Remove `{if}`/`{end}` markers from the final prompt. Also pass `model` from registry entry if set (via Agent tool's `model` parameter).

7. Update registry entry's `taskId` from the background Agent task. Write registry.
8. Tell user: agent `<id>` resumed on branch `<branch>`.

## `retry <id>`

1. Look up agent in registry (prefix match). Must have status `stopped`/`failed`/`unknown`. Reject otherwise.
2. Save the original `description`, `verifyCommand`, `commitFormat`, `model`, `effort`, `color`, and `maxTurns` from the entry.
3. Generate a NEW agent ID.
4. Add new entry to registry (using standard schema from Spawn step 4) with original description and all saved fields, status `running`. Write registry.
5. Run `TaskCreate` (subject, description, activeForm) then spawn `Agent` (same params as Spawn step 5, passing through all saved fields). Update the entry's `taskId` from the Agent task. Write registry.
6. Tell user: "Retrying as new agent `<new_id>` (original: `<old_id>`). Original agent preserved in history."

## `diff <id>`

1. Look up agent in registry (prefix match). If not found, show available IDs.
2. Get the branch name. If no branch, reject: "No branch found for this agent."
3. Run `git diff {defaultBranch}...<branch> --stat` to show file-level summary.
4. Run `git diff {defaultBranch}...<branch>` to show full diff.
5. Display the stat summary first, then the full diff (truncate if extremely long — show first 200 lines and note if truncated).

## `logs <id>`

1. Look up agent in registry (prefix match).
2. Read `.claude/agents/<id>-result.txt` — display if exists.
3. If `taskId` is not null, find the agent's subagent transcript: search for files matching `~/.claude/projects/*/subagents/agent-*.jsonl` using Glob. Look for the transcript that corresponds to the agent's `taskId`. If `taskId` is null, skip to step 5.
4. If transcript found, read it and extract a summary:
   - List tools used (Read, Write, Edit, Bash, etc.) with counts
   - Show files read/modified
   - Show bash commands executed
   - Show any errors encountered
5. If no transcript found and branch is not null, check git log on the branch: `git log {defaultBranch}..<branch> --oneline --stat`. If branch is null, say "No branch or transcript available."
6. Display: **Agent ID** | **Status** | **Description** | **Activity Summary** | **Files Touched** | **Errors (if any)**

## `batch "task1" "task2" ...`

1. Parse arguments — use shell-style quote parsing. Each quoted string is a separate task description. Unquoted words are joined as a single task. If no tasks parsed, reject: "Usage: `/agent batch \"task one\" \"task two\" ...`"
2. For each task: generate a unique ID, add entry to registry (using standard schema from Spawn step 4) with status `running`. Write registry once with all new entries.
3. For each task: run `TaskCreate` (subject, description, activeForm) then spawn `Agent` (same params as Spawn step 5). Update the entry's `taskId` from the Agent task. Write registry after each spawn to persist `taskId`.
4. Display table of all spawned agents: **ID | Description | Status**
5. Tell user: "Spawned {N} agents. Use `/agent list` to monitor."

**Batch flags:** `batch` also supports `--model`, `--effort`, and `--max-turns` flags. If provided, they apply to ALL agents in the batch. Place flags before the task strings: `/agent batch --model sonnet "task one" "task two"`.

## `note <id> "text"`

1. Look up agent in registry (prefix match).
2. Parse the note text from arguments (everything after the ID). If no text provided, reject: "Usage: `/agent note <id> \"your note text\"`"
3. Add/append to a `notes` array in the registry entry: `{ text, timestamp: <ISO now> }`.
4. Write registry. Confirm: "Note added to agent `<id>`."
5. When displaying agent details (in `switch`, `history`), show notes if present.

## `watch <id>`

1. Look up agent in registry (prefix match). Must have status `running`. Reject otherwise.
2. If `taskId` is null, reject: "Agent has no task handle. Try `/agent list` to refresh status."
3. Tell user: "Watching agent `<id>`... (up to 5 minutes, Ctrl+C to stop)"
4. Try `TaskOutput` with `block: true, timeout: 300000` (single blocking call, 5 minutes max). If `TaskOutput` fails or is unavailable (deprecated), fall back to polling: check `.claude/agents/<id>-result.txt` every 10 seconds using `Bash(sleep 10)` + Read, for up to 30 iterations (5 minutes). If the result file appears during polling, treat as completed.
5. Handle the result:
   - If completed → parse result file (if missing, update registry to `completed` with no file details and note "Result file not found — agent may have failed to write it")
     - If branch is not null, run `git diff {defaultBranch}...<branch> --stat` to preview changes. If branch is null, say "Agent completed but no branch was recorded."
     - Show the diff summary to the user
     - Ask user explicitly: "Agent completed. Merge branch `<branch>` into current branch?" — wait for confirmation. Do NOT auto-merge. (Skip merge prompt if branch is null.)
     - If user confirms → check working tree is clean (`git status --porcelain`), then run `git merge <branch>`. On success → update status to `merged`, write registry, suggest `/agent clean`. On conflict → tell user, suggest `git merge --abort`
     - If user declines → tell user: "Skipped merge. Use `/agent merge <id>` later or `/agent diff <id>` to review."
   - If errored → update registry to `failed`, write registry. Tell user: "Agent failed. Use `/agent logs <id>` to investigate or `/agent retry <id>` to try again."
   - If still running (timeout reached) → say: "Agent still running after 5 minutes. Use `/agent watch <id>` again or `/agent list` to check."

## `rebase <id>`

1. Look up agent in registry (prefix match). Must have status `completed`/`unknown`/`stopped`. Reject if `running`/`merged`/`failed` with reason.
2. If `branch` is null, reject: "No branch recorded for this agent." Otherwise, verify branch exists (`git branch --list <branch>`). If not, say so.
3. Check working tree is clean (`git status --porcelain`). If dirty, reject: "Working tree has uncommitted changes. Commit or stash first."
4. Run `git fetch origin {defaultBranch}` (ignore errors if no remote).
5. Run `git checkout <branch> && git rebase {defaultBranch}`.
6. On success → run `git checkout -` to return to original branch. Tell user: "Branch `<branch>` rebased onto `{defaultBranch}`. Ready to merge with `/agent merge <id>`."
7. On conflict → tell user the conflicting files, suggest `git rebase --abort` or manual resolution.

## `export <id>`

1. Look up agent in registry (prefix match).
2. Get branch name. If no branch, reject.
3. Run `mkdir -p .claude/agents && git format-patch {defaultBranch}..<branch> --stdout > .claude/agents/<id>.patch`
4. Tell user: "Patch exported to `.claude/agents/<id>.patch`. Apply with `git am < .claude/agents/<id>.patch`."

## `stats`

1. Read registry.
2. Calculate:
   - **Total spawned:** count of all agents
   - **By status:** count per status (running/completed/stopped/failed/merged/unknown)
   - **Success rate:** completed+merged / total (exclude running). If no non-running agents, show "N/A"
   - **Most active day:** group by date of `createdAt`, find max
   - **Avg files changed:** average length of `filesChanged` arrays (for completed/merged). If none, show "N/A"
   - **Models used:** count per model value (for agents with `model` set)
3. Display as a formatted summary panel.

---

## Spawn (default — no command match)

Handles: plain task descriptions, `--template <name>`, `--model <model>`, `--effort <level>`, `--color <color>`, and `--max-turns <N>` flags.

1. Parse flags from arguments:
   - `--template <name>`: read `.claude/agents/templates/<name>.json`. If not found, list available templates and abort. Use template's description prefix + remaining args as description. Store `verifyCommand` and `commitFormat` from the template.
   - `--model <model>`: one of `haiku`, `sonnet`, `opus`. Store for Agent tool's `model` parameter and registry. Falls back to `CLAUDE_PLUGIN_OPTION_DEFAULT_MODEL` env var if not specified.
   - `--effort <level>`: one of `low`, `medium`, `high`, `max`. **Registry metadata only** — the worker always runs at `effort: high` (set in its definition). This flag is stored for tracking/display purposes. Falls back to `CLAUDE_PLUGIN_OPTION_DEFAULT_EFFORT` env var if not specified.
   - `--color <color>`: one of `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan`. Store in registry.
   - `--max-turns <N>`: positive integer. **Registry metadata only** — the worker always uses `maxTurns: 200` (set in its definition). This flag is stored for tracking/display purposes.
   - Everything else (after removing flags) is the task description. If no flags matched, use full `$ARGUMENTS` as description. Set unspecified flags to `null`.
2. Generate ID, read registry.
3. `TaskCreate` with subject (60 chars max), description, activeForm (present continuous).
4. Add entry to registry: `{ id, taskId: null, description, status: "running", branch: null, commit: null, commitMessage: null, createdAt: <ISO now>, completedAt: null, filesChanged: [], notes: [], verifyCommand, commitFormat, model, effort, color, maxTurns }`. Write registry.
5. Spawn `Agent` with `subagent_type: "agent-manager:worker"`, and if `model` is set pass it via the Agent tool's `model` parameter. The prompt:

```
**Task:** {description} | **Agent ID:** {id}
{if verifyCommand}

**Verify command:** `{verifyCommand}`
{end}
{if commitFormat}

**Commit format:** `{commitFormat}`
{end}

**CRITICAL — after committing, write the result file to the ORIGINAL repo (not worktree):**

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
FILES=$(git diff {defaultBranch}..HEAD --name-only 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
DIFF_STAT=$(git diff {defaultBranch}..HEAD --stat 2>/dev/null | tail -5)
COMMIT_LOG=$(git log {defaultBranch}..HEAD --oneline 2>/dev/null)
mkdir -p {repo_absolute_path}/.claude/agents
cat > {repo_absolute_path}/.claude/agents/{id}-result.txt << RESULT_EOF
branch: $BRANCH
commit: $COMMIT
commitMessage: $COMMIT_MSG
filesChanged: $FILES
summary: Completed task — {short description}
commitLog: $COMMIT_LOG
diffStat: $DIFF_STAT
RESULT_EOF
```

**Template handling:** Include `{if ...}` blocks only when the value is set. Remove `{if}`/`{end}` markers from the final prompt.

**Note:** The `agent-manager:worker` subagent already has `background: true`, `isolation: worktree`, and `effort: high` in its definition. The 5-phase execution process (Analyze, Plan, Implement, Verify, Commit) is in the worker's system prompt — do NOT duplicate it in the task prompt.

6. Update registry entry's `taskId` from the background Agent task (NOT TaskCreate). Write registry.
7. Tell user: agent `<id>` spawned. Show model/color if set. Available commands: `list`, `switch`, `stop`, `merge`, `resume`, `retry`, `diff`, `logs`, `batch`, `note`, `watch`, `rebase`, `export`, `stats`, `history`, `clean`.
