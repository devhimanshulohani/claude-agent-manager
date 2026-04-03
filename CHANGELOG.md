# Changelog

## 3.0.0 (2026-04-03)

### Breaking Changes

- Registry version bumped to 2 (auto-migrates from v1)
- Spawned agents now use custom `agent-manager:worker` subagent type instead of `general-purpose`

### Features

- **Custom worker subagent**: Ships `agents/worker.md` with `background: true`, `isolation: worktree`, `effort: high`, `maxTurns: 200`, `memory: project`, and `disallowedTools`. The 5-phase execution process lives in the worker's system prompt, keeping spawn prompts lean.
- **Model selection**: `--model haiku|sonnet|opus` flag on spawn/batch to control which model the agent uses
- **Effort level**: `--effort low|medium|high|max` flag on spawn/batch (registry metadata — worker runs at `high`)
- **Color tagging**: `--color <color>` flag for visual agent identification in the UI
- **Max turns**: `--max-turns <N>` flag on spawn/batch (registry metadata — worker default: 200)
- **SubagentStop hook**: Registry auto-updates when worker agents complete — no more polling needed. Hook at `hooks/hooks.json` calls `bin/update-registry.sh`.
- **Worker memory**: Worker accumulates codebase patterns and conventions across tasks at `.claude/agent-memory/worker/`
- **Tool enforcement**: Worker uses `disallowedTools: EnterPlanMode, ExitPlanMode, AskUserQuestion` — enforced at tool level
- **User config**: Plugin prompts for `default_model` and `default_effort` preferences when enabled
- **Watch fallback**: `watch` command falls back to result-file polling if TaskOutput is unavailable (preparing for TaskOutput deprecation)

### Improvements

- `effort: high` frontmatter on the skill itself for better quality orchestration
- Status detection now checks result file first (via Read) before falling back to TaskOutput — follows TaskOutput deprecation guidance
- `switch` and `list` check result files eagerly to detect completion without TaskOutput
- Spawn prompt dramatically simplified — phases are in the worker subagent, only task-specific details in the prompt
- `retry` preserves `model`, `effort`, `color`, and `maxTurns` from the original agent
- `batch` supports `--model`, `--effort`, and `--max-turns` flags applied to all agents
- `history` and `switch` show model info when set
- `stats` shows model usage breakdown
- Plugin ships `bin/` executables for hook scripts
- Ask-once default branch detection — works with main, master, develop, or any branch name
- Registry v1→v2 auto-migration preserves existing agent history
- Atomic registry writes (write to .tmp then rename) prevent corruption
- Pre-flight git repo check with clear error message
- Flag validation rejects invalid `--model`, `--color`, `--effort`, `--max-turns` values
- Hook script rewritten with `node -e` for reliable JSON parsing and file locking

## 2.1.1 (2026-03-05)

### Fixes

- Spawn and resume now store background Agent taskId instead of TaskCreate taskId — fixes list/switch/watch polling
- `retry` rejects all non-retryable statuses, not just `running`
- `list` handles null branch gracefully (marks as `unknown` instead of `failed`)
- `watch` description corrected — asks for user confirmation, not auto-merge

## 2.1.0 (2026-03-05)

### Improvements

- **structured decomposition**: Agent spawn and resume prompts now use a 5-phase approach (Analyze → Plan → Implement → Verify → Commit & Report) instead of flat instructions
- Agents break tasks into 3–8 ordered steps before implementing, with fallback approaches for risky steps
- Incremental verification after each step prevents cascading errors
- Resume agents analyze previous progress before planning remaining work
- Commit and result-file write happen in the same bash block to prevent orphaned commits
- Template `verifyCommand` and `commitFormat` now injected into spawn prompts via conditional blocks
- Resume prompt fetches branch from remote before checkout to handle worktree isolation

## 2.0.0 (2026-03-05)

### Features

- **resume**: Resume stopped/failed agents on their existing branch with context
- **retry**: Re-spawn failed agents with the same task from scratch
- **diff**: Quick inline diff preview without switching to an agent
- **logs**: Summarized activity log from agent transcripts
- **batch**: Spawn multiple agents in parallel with one command
- **note**: Attach notes to agent entries for tracking context
- **watch**: Poll a running agent until completion, with merge confirmation
- **rebase**: Rebase agent branch onto latest main before merging
- **export**: Export agent changes as a `.patch` file
- **stats**: Lifetime statistics — total spawned, success rate, most active day
- **templates**: Spawn agents with pre-defined task templates (`--template`)

### Improvements

- Registry entries now include `notes` array
- Spawn command shows all available commands in confirmation
- Internal prompt restructured with 5-phase heading (v3)

## 1.0.0 (2026-03-05)

### Features

- Spawn autonomous background agents in isolated git worktrees
- Persistent agent registry across sessions (`.claude/agents/registry.json`)
- Commands: spawn, list, switch, stop, merge, history, clean
- Automatic status detection for agents from previous sessions
- Merge completed agent branches back into working branch
