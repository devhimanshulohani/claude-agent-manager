---
name: agent
description: Spawn and manage autonomous background agents
argument-hint: "task" | list | switch <id> | stop <id> | merge <id> | resume <id> | retry <id> | diff <id> | logs <id> | batch | note <id> | watch <id> | rebase <id> | export <id> | stats | history | clean
disable-model-invocation: true
allowed-tools: Agent, Bash, Read, Edit, Write, Glob, Grep, TaskOutput, TaskStop, TaskCreate, TaskUpdate, TaskList
---

# Agent Manager v3

Parse `$ARGUMENTS` and execute the matching command below. Persistent state lives in `.claude/agents/registry.json` (source of truth). Task system is for live monitoring only.

**Registry:** Read `.claude/agents/registry.json` — if missing/corrupt, default to `{ "version": 1, "agents": [] }`. Always `mkdir -p .claude/agents` before writing.
**Agent ID:** Generate via `date +%s | shasum | head -c 6` (6-char hex).
**Age format:** `<N>m ago` / `<N>h ago` / `<N>d ago` relative to `createdAt`.
**Templates dir:** `.claude/agents/templates/` — JSON files with `{ name, description, verifyCommand, commitFormat }`.

---

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

---

## `resume <id>`

Resume a stopped/failed/unknown agent — re-spawns in the same branch with context.

1. Look up agent in registry. Must have status `stopped`/`failed`/`unknown`. Reject if `running`/`completed`/`merged`.
2. Verify branch exists (`git branch --list <branch>`). If not, say "Branch no longer exists. Use `/agent retry <id>` to start fresh."
3. Read `.claude/agents/<id>-result.txt` if exists — extract any partial progress info.
4. Get the list of changes already made: `git log main..<branch> --oneline` and `git diff main..<branch> --stat`
5. Update registry: status → `running`, clear `completedAt`. Write registry.
6. `TaskCreate` with subject: `Resume: <original description>` (60 chars max), activeForm (present continuous).
7. Spawn `Agent` with `subagent_type: "general-purpose"`, `run_in_background: true`, `isolation: "worktree"`, prompt:

```
You are an autonomous agent RESUMING previous work. **Task:** {description} | **Agent ID:** {id}

**Previous progress on branch `{branch}`:**
{git log output}
{git diff stat output}
{partial result file contents if any}

You MUST work through these 5 phases in order. Do not skip phases.

## Phase 1 — Analyze Previous Progress
- Fetch and checkout the existing branch: `git fetch origin {branch} 2>/dev/null; git checkout {branch} 2>/dev/null || git checkout -b {branch} origin/{branch}`
- Read the changed files and understand what was already completed
- Identify what remains to be done vs what is already done
- Do NOT redo completed work — only pick up where it left off

## Phase 2 — Plan Remaining Work
- Break the remaining work into 3–8 ordered steps
- For each step: what files change, what the change is, and any risks
- Identify dependencies between steps (what must happen first)
- If any step seems risky, note a fallback approach

## Phase 3 — Implement
- Execute steps in the order you planned
- After each step, verify it didn't break anything (read back the file, check syntax)
- If a step fails, try the fallback before moving on
- Do NOT batch all changes blindly — work incrementally

## Phase 4 — Verify
- Auto-detect the build system and run the appropriate check:
  - `package.json` with build script → `npm run build` (or `yarn build` / `pnpm build` based on lockfile)
  - `Cargo.toml` → `cargo check`
  - `go.mod` → `go build ./...`
  - `pyproject.toml` / `setup.py` → `python -m py_compile` on changed files
  - `Makefile` → `make`
- If no recognizable build system, skip verification and note it in the summary
- If the check fails, fix the issues and re-run until it passes

## Phase 5 — Commit & Report
- Commit with conventional format: `type(scope): subject`
- CRITICAL — in the SAME bash block, after committing, write the result file to the ORIGINAL repo (not worktree):

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
summary: Resumed and completed task — {short description}
RESULT_EOF

You are in an isolated worktree. Make changes freely. Work autonomously — no questions, make reasonable decisions.
```

8. Update registry entry's `taskId`. Write registry.
9. Tell user: agent `<id>` resumed on branch `<branch>`.

## `retry <id>`

Re-spawn a failed agent with the same task but completely fresh context.

1. Look up agent in registry. Must have status `stopped`/`failed`/`unknown`. Reject if `running`.
2. Save the original `description` from the entry.
3. Generate a NEW agent ID.
4. Add new entry to registry with original description, status `running`. Write registry.
5. Spawn using the standard **Spawn** flow below with the original description.
6. Tell user: "Retrying as new agent `<new_id>` (original: `<old_id>`). Original agent preserved in history."

## `diff <id>`

Quick inline diff preview of an agent's changes.

1. Look up agent in registry (prefix match). If not found, show available IDs.
2. Get the branch name. If no branch, say "No branch found for this agent."
3. Run `git diff main...<branch> --stat` to show file-level summary.
4. Run `git diff main...<branch>` to show full diff.
5. Display the stat summary first, then the full diff (truncate if extremely long — show first 200 lines and note if truncated).

## `logs <id>`

Show a summarized activity log of what the agent did.

1. Look up agent in registry (prefix match).
2. Read `.claude/agents/<id>-result.txt` — display if exists.
3. Find the agent's subagent transcript: search for files matching `~/.claude/projects/*/subagents/agent-*.jsonl` using Glob. Look for the transcript that corresponds to the agent's `taskId`.
4. If transcript found, read it and extract a summary:
   - List tools used (Read, Write, Edit, Bash, etc.) with counts
   - Show files read/modified
   - Show bash commands executed
   - Show any errors encountered
5. If no transcript found, check git log on the branch: `git log main..<branch> --oneline --stat`
6. Display: **Agent ID** | **Status** | **Description** | **Activity Summary** | **Files Touched** | **Errors (if any)**

## `batch "task1" "task2" ...`

Spawn multiple agents at once for parallel work.

1. Parse arguments — split by quoted strings. Each quoted string is a separate task description.
2. For each task:
   - Generate a unique ID
   - Add entry to registry with status `running`
3. Write registry once with all new entries.
4. For each task, spawn using the standard **Spawn** flow (TaskCreate + Agent).
5. Display table of all spawned agents: **ID | Description | Status**
6. Tell user: "Spawned {N} agents. Use `/agent list` to monitor."

## `note <id> "text"`

Attach a note to an agent entry.

1. Look up agent in registry (prefix match).
2. Parse the note text from arguments (everything after the ID).
3. Add/append to a `notes` array in the registry entry: `{ text, timestamp: <ISO now> }`.
4. Write registry. Confirm: "Note added to agent `<id>`."
5. When displaying agent details (in `switch`, `history`), show notes if present.

## `watch <id>`

Poll a running agent and auto-merge when complete.

1. Look up agent in registry. Must have status `running`. Reject otherwise.
2. Enter a poll loop (max 30 iterations, 10s apart):
   - Try `TaskOutput` with `block: true, timeout: 10000`
   - If completed → parse result file, update registry to `completed`
   - Run `git diff main...<branch> --stat` to preview changes
   - Show the diff summary to the user
   - Ask user explicitly: "Agent completed. Merge branch `<branch>` into current branch?" — wait for confirmation. Do NOT auto-merge.
   - If user confirms → run `git merge <branch>`, update status to `merged`, write registry, suggest `/agent clean`
   - If user declines → tell user: "Skipped merge. Use `/agent merge <id>` later or `/agent diff <id>` to review."
   - Break loop.
   - If still running, continue polling.
3. If max iterations reached, say: "Agent still running after 5 minutes. Use `/agent watch <id>` again or `/agent list` to check."

## `rebase <id>`

Rebase an agent's branch onto latest main before merging.

1. Look up agent in registry. Must have status `completed`/`unknown`. Reject if `running`.
2. Verify branch exists. If not, say so.
3. Run `git fetch origin main` (ignore errors if no remote).
4. Run `git checkout <branch> && git rebase main`.
5. On success → run `git checkout -` to return to original branch. Tell user: "Branch `<branch>` rebased onto main. Ready to merge with `/agent merge <id>`."
6. On conflict → tell user the conflicting files, suggest `git rebase --abort` or manual resolution.

## `export <id>`

Export agent's changes as a patch file.

1. Look up agent in registry (prefix match).
2. Get branch name. If no branch, reject.
3. Run `git format-patch main..<branch> --stdout > .claude/agents/<id>.patch`
4. Tell user: "Patch exported to `.claude/agents/<id>.patch`. Apply with `git am < .claude/agents/<id>.patch`."

## `stats`

Show lifetime agent statistics.

1. Read registry.
2. Calculate:
   - **Total spawned:** count of all agents
   - **By status:** count per status (running/completed/stopped/failed/merged/unknown)
   - **Success rate:** completed+merged / total (exclude running)
   - **Most active day:** group by date of `createdAt`, find max
   - **Avg files changed:** average length of `filesChanged` arrays (for completed/merged)
3. Display as a formatted summary panel.

---

## Spawn (default — no command match)

Handles: plain task descriptions and `--template <name>` flag.

1. Check if arguments contain `--template <name>`:
   - If yes, read `.claude/agents/templates/<name>.json`. If not found, list available templates. Use template's description prefix + remaining args as description. Store `verifyCommand` and `commitFormat` from the template for injection into the prompt.
   - If no, use full `$ARGUMENTS` as the task description. Set `verifyCommand` and `commitFormat` to `null`.
2. Generate ID, read registry.
3. `TaskCreate` with subject (60 chars max), description, activeForm (present continuous).
4. Add entry to registry: `{ id, taskId: null, description, status: "running", branch: null, worktreePath: null, commit: null, commitMessage: null, createdAt: <ISO now>, completedAt: null, filesChanged: [], notes: [] }`. Write registry.
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
FILES=$(git diff --name-only HEAD~1 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
mkdir -p {repo_absolute_path}/.claude/agents
cat > {repo_absolute_path}/.claude/agents/{id}-result.txt << RESULT_EOF
branch: $BRANCH
commit: $COMMIT
commitMessage: $COMMIT_MSG
filesChanged: $FILES
summary: Completed task — {short description}
RESULT_EOF

You are in an isolated worktree. Make changes freely. Work autonomously — no questions, make reasonable decisions.
```

6. Update registry entry's `taskId` from TaskCreate. Write registry.
7. Tell user: agent `<id>` spawned. Available commands: `list`, `switch`, `stop`, `merge`, `resume`, `retry`, `diff`, `logs`, `batch`, `note`, `watch`, `rebase`, `export`, `stats`, `history`, `clean`.
