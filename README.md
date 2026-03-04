# Claude Agent Manager

A Claude Code plugin for spawning and managing autonomous background agents with persistent state across sessions.

## What it does

- **Spawn** background agents that work in isolated git worktrees
- **Track** agent status with a persistent registry (`.claude/agents/registry.json`)
- **Resume** stopped or failed agents from where they left off
- **Merge** completed agent work back into your main branch
- **Monitor** agent activity with logs, diffs, and watch mode
- **Clean up** finished agents and their worktrees

## Install

```bash
claude plugin install agent-manager
```

Or test locally:

```bash
claude --plugin-dir /path/to/claude-agent-manager
```

## Commands

### Core

| Command | Description |
|---------|-------------|
| `/agent-manager:agent "task"` | Spawn a new background agent |
| `/agent-manager:agent list` | Show all agents and their status |
| `/agent-manager:agent switch <id>` | View details of a specific agent |
| `/agent-manager:agent stop <id>` | Stop a running agent |
| `/agent-manager:agent merge <id>` | Merge a completed agent's branch |
| `/agent-manager:agent history` | Show full agent history |
| `/agent-manager:agent clean` | Remove finished agents and worktrees |

### Recovery

| Command | Description |
|---------|-------------|
| `/agent-manager:agent resume <id>` | Resume a stopped/failed agent on its existing branch |
| `/agent-manager:agent retry <id>` | Re-spawn a failed agent with the same task from scratch |

### Inspection

| Command | Description |
|---------|-------------|
| `/agent-manager:agent diff <id>` | Quick inline diff preview of agent's changes |
| `/agent-manager:agent logs <id>` | Summarized activity log of what the agent did |
| `/agent-manager:agent stats` | Lifetime stats — total spawned, success rate, etc. |

### Advanced

| Command | Description |
|---------|-------------|
| `/agent-manager:agent batch "task1" "task2"` | Spawn multiple agents in parallel |
| `/agent-manager:agent note <id> "text"` | Attach a note to an agent |
| `/agent-manager:agent watch <id>` | Poll a running agent until completion |
| `/agent-manager:agent rebase <id>` | Rebase agent branch onto latest main |
| `/agent-manager:agent export <id>` | Export changes as a `.patch` file |

### Templates

Spawn with a pre-defined template:

```
/agent-manager:agent --template api "add user profile endpoint"
```

Templates are stored in `.claude/agents/templates/` as JSON files.

## How it works

1. Each spawned agent runs in an isolated git worktree
2. Agents work autonomously — reading code, making changes, running checks, and committing
3. Results are written back to a registry file so state persists across sessions
4. Resume agents that failed, or retry them from scratch
5. When ready, merge the agent's branch back into your working branch

## License

MIT
