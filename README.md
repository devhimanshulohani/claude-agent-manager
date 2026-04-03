# Claude Agent Manager

A Claude Code plugin for spawning and managing autonomous background agents with persistent state across sessions.

## What it does

- **Spawn** background agents that work in isolated git worktrees
- **Track** agent status with a persistent registry (`.claude/agents/registry.json`)
- **Auto-detect completion** via hooks — registry updates in real-time when agents finish
- **Resume** stopped or failed agents from where they left off
- **Merge** completed agent work back into your main branch
- **Monitor** agent activity with logs, diffs, and watch mode
- **Learn** from previous tasks via persistent worker memory

## Install

```bash
claude plugin install agent-manager
```

When enabling, you'll be prompted for optional defaults:
- **Default model** — `haiku`, `sonnet`, or `opus` (leave empty to inherit from session)
- **Default effort** — `low`, `medium`, `high`, or `max` (leave empty for `high`)

Or test locally:

```bash
claude --plugin-dir /path/to/claude-agent-manager
```

### Requirements

- **Git** — agents work in isolated git worktrees
- **Node.js** — used by the hook script (always available since Claude Code runs on Node)
- No other external dependencies

## Commands

### Core

| Command | Description |
|---------|-------------|
| `/agent "task"` | Spawn a new background agent |
| `/agent list` | Show all agents and their status |
| `/agent switch <id>` | View details of a specific agent |
| `/agent stop <id>` | Stop a running agent |
| `/agent merge <id>` | Merge a completed agent's branch |
| `/agent history` | Show full agent history |
| `/agent clean` | Remove finished agents and worktrees |

### Recovery

| Command | Description |
|---------|-------------|
| `/agent resume <id>` | Resume a stopped/failed agent on its existing branch |
| `/agent retry <id>` | Re-spawn a failed agent with the same task from scratch |

### Inspection

| Command | Description |
|---------|-------------|
| `/agent diff <id>` | Quick inline diff preview of agent's changes |
| `/agent logs <id>` | Summarized activity log of what the agent did |
| `/agent stats` | Lifetime stats — total spawned, success rate, etc. |

### Advanced

| Command | Description |
|---------|-------------|
| `/agent batch "task1" "task2"` | Spawn multiple agents in parallel |
| `/agent note <id> "text"` | Attach a note to an agent |
| `/agent watch <id>` | Poll a running agent until completion |
| `/agent rebase <id>` | Rebase agent branch onto latest main |
| `/agent export <id>` | Export changes as a `.patch` file |

### Templates

Spawn with a pre-defined template:

```
/agent --template api "add user profile endpoint"
```

Templates are stored in `.claude/agents/templates/` as JSON files:

```json
{
  "name": "api",
  "description": "API endpoint template",
  "verifyCommand": "npm test",
  "commitFormat": "feat(api): {description}"
}
```

Required fields: `name`, `description`. Optional: `verifyCommand` (overrides Phase 4 auto-detection), `commitFormat` (overrides conventional commit format).

### Spawn Flags

| Flag | Values | Description |
|------|--------|-------------|
| `--model` | `haiku`, `sonnet`, `opus` | Choose which model the agent uses |
| `--effort` | `low`, `medium`, `high`, `max` | Effort level metadata (worker runs at `high`) |
| `--color` | `red`, `blue`, `green`, `yellow`, `purple`, `orange`, `pink`, `cyan` | Visual color for agent identification |
| `--max-turns` | `<number>` | Max turns metadata (worker default: 200) |
| `--template` | `<name>` | Use a pre-defined template |

> **Note:** `--model` is the only flag that changes agent behavior at runtime (via the Agent tool's `model` parameter). `--effort` and `--max-turns` are stored in the registry for tracking but the worker subagent always uses `effort: high` and `maxTurns: 200` from its definition. `--color` sets the agent's display color.

**Examples:**

```
/agent --model sonnet "refactor the auth module"
/agent --model haiku --color blue "add JSDoc comments to utils/"
/agent --max-turns 50 "quick formatting fix"
/agent batch --model sonnet "task one" "task two"
```

## How it works

1. Each spawned agent runs as a custom `worker` subagent in an isolated git worktree
2. The worker follows a structured 5-phase process:
   - **Analyze** — read project conventions, identify relevant files
   - **Plan** — break task into 3-8 ordered steps with fallbacks
   - **Implement** — execute incrementally, verify after each step
   - **Verify** — auto-detect build system and run checks (or use template's `verifyCommand`)
   - **Commit** — conventional commit, write result file back to main repo
3. A `SubagentStop` hook auto-updates the registry when agents complete
4. Workers accumulate project knowledge via persistent memory (`.claude/agent-memory/worker/`)
5. Resume agents that failed, or retry them from scratch
6. When ready, merge the agent's branch back into your working branch

## Plugin Structure

```
claude-agent-manager/
├── .claude-plugin/
│   ├── plugin.json          # Plugin manifest with userConfig
│   └── marketplace.json     # Marketplace metadata
├── agents/
│   └── worker.md            # Custom worker subagent (background, worktree, memory)
├── skills/
│   └── agent/
│       └── SKILL.md         # Main skill with all commands
├── hooks/
│   └── hooks.json           # SubagentStop hook for auto-registry updates
├── bin/
│   └── update-registry.sh   # Registry update script called by hook
├── README.md
├── CHANGELOG.md
└── LICENSE
```

## Tips

### First-time setup

On your first `/agent` command in a repo, the plugin asks for your default branch (e.g., `main`, `master`, `develop`). This is stored in the registry and used for all git operations. You only get asked once per project.

### Monorepos with submodules

Agents run in git worktrees. For monorepos with submodules, `cd` into the submodule before spawning agents — this ensures the worktree is created for that specific repo:

```bash
cd my-monorepo/frontend    # cd into the submodule
claude                     # start Claude Code here
/agent "add dark mode"     # agent works on frontend repo only
```

### Environment files in worktrees

Agents run in isolated git worktrees, which don't include gitignored files like `.env`. If your project needs environment variables or config files in agent worktrees, create a `.worktreeinclude` file at your project root:

```
.env
.env.local
config/secrets.json
```

Files matching these patterns that are also gitignored will be automatically copied into each agent's worktree.

## License

MIT
