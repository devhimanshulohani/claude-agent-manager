# Changelog

## 2.0.0 (2026-03-05)

### Features

- **resume**: Resume stopped/failed agents on their existing branch with context
- **retry**: Re-spawn failed agents with the same task from scratch
- **diff**: Quick inline diff preview without switching to an agent
- **logs**: Summarized activity log from agent transcripts
- **batch**: Spawn multiple agents in parallel with one command
- **note**: Attach notes to agent entries for tracking context
- **watch**: Poll a running agent and auto-merge on completion
- **rebase**: Rebase agent branch onto latest main before merging
- **export**: Export agent changes as a `.patch` file
- **stats**: Lifetime statistics — total spawned, success rate, most active day
- **templates**: Spawn agents with pre-defined task templates (`--template`)

### Improvements

- Registry entries now include `notes` array
- Spawn command shows all available commands in confirmation
- Bumped to Agent Manager v3

## 1.0.0 (2026-03-05)

### Features

- Spawn autonomous background agents in isolated git worktrees
- Persistent agent registry across sessions (`.claude/agents/registry.json`)
- Commands: spawn, list, switch, stop, merge, history, clean
- Automatic status detection for agents from previous sessions
- Merge completed agent branches back into working branch
