# Claude Agent Manager

A Claude Code plugin for spawning and managing autonomous background agents with persistent state across sessions.

## What it does

- **Spawn** background agents that work in isolated git worktrees
- **Track** agent status with a persistent registry (`.claude/agents/registry.json`)
- **Merge** completed agent work back into your main branch
- **Clean up** finished agents and their worktrees

## Install

### Option A: Local plugin directory

```bash
claude --plugin-dir /path/to/claude-agent-manager
```

### Option B: Clone and reference

```bash
git clone https://github.com/devhimanshulohani/claude-agent-manager.git
claude --plugin-dir ./claude-agent-manager
```

## Commands

| Command | Description |
|---------|-------------|
| `/agent-manager:agent "task"` | Spawn a new background agent |
| `/agent-manager:agent list` | Show all agents and their status |
| `/agent-manager:agent switch <id>` | View details of a specific agent |
| `/agent-manager:agent stop <id>` | Stop a running agent |
| `/agent-manager:agent merge <id>` | Merge a completed agent's branch |
| `/agent-manager:agent history` | Show full agent history |
| `/agent-manager:agent clean` | Remove finished agents and worktrees |

## How it works

1. Each spawned agent runs in an isolated git worktree
2. Agents work autonomously — reading code, making changes, running checks, and committing
3. Results are written back to a registry file so state persists across sessions
4. When ready, merge the agent's branch back into your working branch

## License

MIT
