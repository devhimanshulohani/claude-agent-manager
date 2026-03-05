---
name: agent
description: Spawn and manage autonomous background agents with persistent state across sessions
argument-hint: '"task" | list | switch <id> | stop <id> | merge <id> | resume <id> | retry <id> | diff <id> | logs <id> | batch | note <id> | watch <id> | rebase <id> | export <id> | stats | history | clean'
disable-model-invocation: true
allowed-tools: Agent, AskUserQuestion, Bash, Read, Edit, Write, Glob, Grep, TaskOutput, TaskStop, TaskCreate, TaskUpdate, TaskList
---

# Agent Manager v3

Parse `$ARGUMENTS` and execute the matching command below. Persistent state lives in `.claude/agents/registry.json` (source of truth). Task system is for live monitoring only.

**Registry:** Read `.claude/agents/registry.json` — if missing/corrupt, default to `{ "version": 1, "agents": [] }`. Always `mkdir -p .claude/agents` before writing.
**Agent ID:** Generate via `echo "$(date +%s)$$.$RANDOM" | shasum | head -c 6` (6-char hex). `$$` (PID) + `$RANDOM` ensures uniqueness even when called multiple times in the same second (e.g., `batch`).
**Age format:** `<N>m ago` / `<N>h ago` / `<N>d ago` relative to `createdAt`.
**Prefix match:** All ID-based commands support prefix matching. If the prefix is ambiguous (matches multiple agents), reject and show the matching IDs. If no match, show all available IDs.
**Templates dir:** `.claude/agents/templates/` — JSON files with required fields `{ name, description }` and optional `{ verifyCommand, commitFormat }`. `verifyCommand` overrides Phase 4 auto-detection; `commitFormat` overrides the default conventional commit format.

---

## `list`

1. Read registry. If empty, say "No agents found. Spawn one with: `/agent "your task"`"
2. For each agent with status `running`:
   - If `taskId` is null → mark as `unknown`, continue
   - Try `TaskOutput` with `block: false, timeout: 3000` using stored `taskId`
   - If task found & completed → check `.claude/agents/<id>-result.txt`, parse it, update entry to `completed` with branch/commit/files/completedAt
   - If task found & still running → leave status as `running`, continue
   - If task found & errored → mark as `failed`
   - If task NOT found (new session) → check result file. If exists, parse & mark `completed`. If not: if `branch` is null → `unknown`. Otherwise check `git branch --list <branch>` — branch exists → `unknown`, no branch → `failed`
3. Write updated registry. Display table: **ID | Status | Description | Branch | Age**

## `switch <id>`

1. Look up agent by ID in registry (prefix match). If not found, show available IDs.
2. If `running` and `taskId` is not null → `TaskOutput` with `block: false, timeout: 5000` and display the latest output to the user. If `running` with null `taskId` → say "Agent is running but has no task handle (spawn may have partially failed). Try `/agent list` to refresh or `/agent stop <id>`."
3. Otherwise → read `.claude/agents/<id>-result.txt` for summary. If file missing, say "No result file yet. Agent may still be in progress or failed without output."
4. Show: status, description, branch. Suggest next actions based on status:
   - `running` → `/agent watch <id>` or `/agent stop <id>`
   - `completed` → `/agent merge <id>`, `/agent diff <id>`
   - `unknown`/`stopped` → `/agent merge <id>`, `/agent diff <id>`, `/agent resume <id>`
   - `failed` → `/agent retry <id>` or `/agent resume <id>`
   - `merged` → `/agent clean`
   - If branch exists (any status), also suggest `git diff main...<branch>`

## `stop <id>`

1. Look up agent in registry (prefix match). If not found, say so. If status is not `running`, reject: "Agent `<id>` is `<status>`, not running."
2. If `taskId` is not null, try `TaskStop` with `task_id` (ignore errors if gone). If `taskId` is null, skip — just update status.
3. Update registry: status → `stopped`, set `completedAt`. Write registry. Confirm.

## `history`

1. Read registry. If empty, say "No agent history found"
2. Display ALL agents sorted by `createdAt` desc. Table: **ID | Status | Description | Branch | Commit Message | Date**. Show "—" for null/empty commit messages. Show notes count if agent has notes (e.g., "2 notes").

## `clean`

1. Read registry. Filter agents with status `completed`/`stopped`/`merged`/`failed`/`unknown`
2. For each: delete `.claude/agents/<id>-result.txt` and `.claude/agents/<id>.patch` (if exists), delete branch if `merged` and `branch` is not null (`git branch -d <branch>`). Ignore errors. (Worktrees from `isolation: "worktree"` are auto-managed by Claude Code.)
3. Remove entries from registry, write it. Report: "Cleaned up N agent(s). M still running."

## `merge <id>`

1. Look up agent (prefix match). If not found or status not `completed`/`unknown`/`stopped`, reject with reason.
2. If `branch` is null, reject: "No branch recorded for this agent." Otherwise, verify branch exists (`git branch --list <branch>`). If not, say so.
3. Check working tree is clean (`git status --porcelain`). If dirty, reject: "Working tree has uncommitted changes. Commit or stash first."
4. Run `git checkout main && git merge <branch>`. On success → update status to `merged`, write registry, suggest `/agent clean`. On conflict → tell user, suggest `git merge --abort`.

---

## `resume <id>`

1. Look up agent in registry (prefix match). Must have status `stopped`/`failed`/`unknown`/`completed`. Reject if `running`/`merged`.
2. If `branch` is null, say "No branch to resume from. Use `/agent retry <id>` to start fresh." Otherwise, verify branch exists (`git branch --list <branch>`). If not, say "Branch no longer exists. Use `/agent retry <id>` to start fresh."
3. Read `.claude/agents/<id>-result.txt` — this contains the completion context (branch, files changed, summary of what was done). If missing, fall back to `git log main..<branch> --oneline` (1 command only).
4. Update registry: status → `running`, clear `completedAt`. Write registry.
5. `TaskCreate` with subject: `Resume: <original description>` (60 chars max), activeForm (present continuous).
6. Spawn `Agent` with `subagent_type: "general-purpose"`, `run_in_background: true`, `isolation: "worktree"`, prompt:

```
You are an autonomous agent RESUMING previous work. **Task:** {description} | **Agent ID:** {id}

**Previous work summary:**
{result file contents}

You MUST work through these 5 phases in order. Do not skip phases.

## Phase 1 — Analyze Previous Progress
- Fetch and checkout the existing branch: `git fetch origin {branch} 2>/dev/null; git checkout {branch} 2>/dev/null || git checkout -b {branch} origin/{branch} 2>/dev/null || echo "Warning: branch {branch} not found"`
- Read the changed files and understand what was already completed
- Identify what remains to be done vs what is already done
- Do NOT redo completed work — only pick up where it left off

## Phase 2 — Plan
- Break the task into 3–8 ordered implementation steps
- For each step: what files change, what the change is, and any risks
- Identify dependencies between steps (what must happen first)
- If any step seems risky, note a fallback approach

## Phase 3 — Implement
- Execute steps in the order you planned
- After each step, verify it didn't break anything (read back the file, check syntax)
- If a step fails, try the fallback before moving on
- Do NOT batch all changes blindly — work incrementally

## Phase 4 — Verify
{if verifyCommand}
- Run the project-specific verify command: `{verifyCommand}`
{else}
- Auto-detect the build system and run the appropriate check:
  - `package.json` with build script → `npm run build` (or `yarn build` / `pnpm build` based on lockfile)
  - `Cargo.toml` → `cargo check`
  - `go.mod` → `go build ./...`
  - `pyproject.toml` / `setup.py` → `python -m py_compile` on changed files
  - `Makefile` → `make`
- If no recognizable build system, skip verification and note it in the summary
{end}
- If the check fails, fix the issues and re-run until it passes

## Phase 5 — Commit & Report
{if commitFormat}
- Commit with format: `{commitFormat}`
{else}
- Commit with conventional format: `type(scope): subject`
{end}
- CRITICAL — in the SAME bash block, after committing, write the result file to the ORIGINAL repo (not worktree):

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
FILES=$(git diff main..HEAD --name-only 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
DIFF_STAT=$(git diff main..HEAD --stat 2>/dev/null | tail -5)
COMMIT_LOG=$(git log main..HEAD --oneline 2>/dev/null)
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

You are in an isolated worktree. Make changes freely. Work autonomously — no questions, make reasonable decisions. NEVER use EnterPlanMode or ask for permission — execute all 5 phases fully.
```

**Template handling (same as Spawn):** Read `verifyCommand` and `commitFormat` from the registry entry. If set, include only the `{if ...}` block; otherwise include the `{else}` block. Remove `{if}`/`{else}`/`{end}` markers from the final prompt.

7. Update registry entry's `taskId` from the background Agent task. Write registry.
8. Tell user: agent `<id>` resumed on branch `<branch>`.

## `retry <id>`

1. Look up agent in registry (prefix match). Must have status `stopped`/`failed`/`unknown`. Reject otherwise.
2. Save the original `description`, `verifyCommand`, and `commitFormat` from the entry.
3. Generate a NEW agent ID.
4. Add new entry to registry (using standard schema from Spawn step 4) with original description, `verifyCommand`, `commitFormat`, status `running`. Write registry.
5. Run `TaskCreate` (subject, description, activeForm) then spawn `Agent` (same params as Spawn step 5, passing through `verifyCommand`/`commitFormat` for template handling). Update the entry's `taskId` from the Agent task. Write registry.
6. Tell user: "Retrying as new agent `<new_id>` (original: `<old_id>`). Original agent preserved in history."

## `diff <id>`

1. Look up agent in registry (prefix match). If not found, show available IDs.
2. Get the branch name. If no branch, reject: "No branch found for this agent."
3. Run `git diff main...<branch> --stat` to show file-level summary.
4. Run `git diff main...<branch>` to show full diff.
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
5. If no transcript found and branch is not null, check git log on the branch: `git log main..<branch> --oneline --stat`. If branch is null, say "No branch or transcript available."
6. Display: **Agent ID** | **Status** | **Description** | **Activity Summary** | **Files Touched** | **Errors (if any)**

## `batch "task1" "task2" ...`

1. Parse arguments — use shell-style quote parsing. Each quoted string is a separate task description. Unquoted words are joined as a single task. If no tasks parsed, reject: "Usage: `/agent batch \"task one\" \"task two\" ...`"
2. For each task: generate a unique ID, add entry to registry (using standard schema from Spawn step 4) with status `running`. Write registry once with all new entries.
3. For each task: run `TaskCreate` (subject, description, activeForm) then spawn `Agent` (same params as Spawn step 5). Update the entry's `taskId` from the Agent task. Write registry after each spawn to persist `taskId`.
4. Display table of all spawned agents: **ID | Description | Status**
5. Tell user: "Spawned {N} agents. Use `/agent list` to monitor."

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
4. Call `TaskOutput` with `block: true, timeout: 300000` (single blocking call, 5 minutes max).
5. Handle the result:
   - If completed → parse result file (if missing, update registry to `completed` with no file details and note "Result file not found — agent may have failed to write it")
     - If branch is not null, run `git diff main...<branch> --stat` to preview changes. If branch is null, say "Agent completed but no branch was recorded."
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
4. Run `git fetch origin main` (ignore errors if no remote).
5. Run `git checkout <branch> && git rebase main`.
6. On success → run `git checkout -` to return to original branch. Tell user: "Branch `<branch>` rebased onto main. Ready to merge with `/agent merge <id>`."
7. On conflict → tell user the conflicting files, suggest `git rebase --abort` or manual resolution.

## `export <id>`

1. Look up agent in registry (prefix match).
2. Get branch name. If no branch, reject.
3. Run `mkdir -p .claude/agents && git format-patch main..<branch> --stdout > .claude/agents/<id>.patch`
4. Tell user: "Patch exported to `.claude/agents/<id>.patch`. Apply with `git am < .claude/agents/<id>.patch`."

## `stats`

1. Read registry.
2. Calculate:
   - **Total spawned:** count of all agents
   - **By status:** count per status (running/completed/stopped/failed/merged/unknown)
   - **Success rate:** completed+merged / total (exclude running). If no non-running agents, show "N/A"
   - **Most active day:** group by date of `createdAt`, find max
   - **Avg files changed:** average length of `filesChanged` arrays (for completed/merged). If none, show "N/A"
3. Display as a formatted summary panel.

---

## Spawn (default — no command match)

Handles: plain task descriptions and `--template <name>` flag.

1. Check if arguments contain `--template <name>`:
   - If yes, read `.claude/agents/templates/<name>.json`. If not found, list available templates and abort (do not spawn). Use template's description prefix + remaining args as description. Store `verifyCommand` and `commitFormat` from the template for injection into the prompt.
   - If no, use full `$ARGUMENTS` as the task description. Set `verifyCommand` and `commitFormat` to `null`.
2. Generate ID, read registry.
3. `TaskCreate` with subject (60 chars max), description, activeForm (present continuous).
4. Add entry to registry: `{ id, taskId: null, description, status: "running", branch: null, commit: null, commitMessage: null, createdAt: <ISO now>, completedAt: null, filesChanged: [], notes: [], verifyCommand: <from step 1>, commitFormat: <from step 1> }`. Write registry.
5. Spawn `Agent` with `subagent_type: "general-purpose"`, `run_in_background: true`, `isolation: "worktree"`, prompt below.
   **Template handling:** If `verifyCommand` is set, include only the `{if verifyCommand}` block in Phase 4. If `commitFormat` is set, include only the `{if commitFormat}` block in Phase 5. Otherwise include the `{else}` blocks. Remove the `{if}`/`{else}`/`{end}` markers from the final prompt.

```
You are an autonomous agent. **Task:** {description} | **Agent ID:** {id}

You MUST work through these 5 phases in order. Do not skip phases.

## Phase 1 — Analyze
- Read the project's README, CLAUDE.md, or equivalent to understand conventions
- Identify the files and modules relevant to the task
- Map out what needs to change and where (list files + what changes in each)
- Note any project-specific patterns (import style, naming, test conventions)

## Phase 2 — Plan
- Break the task into 3–8 ordered implementation steps
- For each step: what files change, what the change is, and any risks
- Identify dependencies between steps (what must happen first)
- If any step seems risky, note a fallback approach

## Phase 3 — Implement
- Execute steps in the order you planned
- After each step, verify it didn't break anything (read back the file, check syntax)
- If a step fails, try the fallback before moving on
- Do NOT batch all changes blindly — work incrementally

## Phase 4 — Verify
{if verifyCommand}
- Run the project-specific verify command: `{verifyCommand}`
{else}
- Auto-detect the build system and run the appropriate check:
  - `package.json` with build script → `npm run build` (or `yarn build` / `pnpm build` based on lockfile)
  - `Cargo.toml` → `cargo check`
  - `go.mod` → `go build ./...`
  - `pyproject.toml` / `setup.py` → `python -m py_compile` on changed files
  - `Makefile` → `make`
- If no recognizable build system, skip verification and note it in the summary
{end}
- If the check fails, fix the issues and re-run until it passes

## Phase 5 — Commit & Report
{if commitFormat}
- Commit with format: `{commitFormat}`
{else}
- Commit with conventional format: `type(scope): subject`
{end}
- CRITICAL — in the SAME bash block, after committing, write the result file to the ORIGINAL repo (not worktree):

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
FILES=$(git diff main..HEAD --name-only 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
DIFF_STAT=$(git diff main..HEAD --stat 2>/dev/null | tail -5)
COMMIT_LOG=$(git log main..HEAD --oneline 2>/dev/null)
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

You are in an isolated worktree. Make changes freely. Work autonomously — no questions, make reasonable decisions. NEVER use EnterPlanMode or ask for permission — execute all 5 phases fully.
```

6. Update registry entry's `taskId` from the background Agent task (NOT TaskCreate). Write registry.
7. Tell user: agent `<id>` spawned. Available commands: `list`, `switch`, `stop`, `merge`, `resume`, `retry`, `diff`, `logs`, `batch`, `note`, `watch`, `rebase`, `export`, `stats`, `history`, `clean`.

