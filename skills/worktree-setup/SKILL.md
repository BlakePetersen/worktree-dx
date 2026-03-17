---
name: worktree-setup
description: "Manage git worktrees with automatic stack-aware setup, env syncing, and self-improving DX"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree.sh:*)", "Bash(bash:*)", "Bash(git worktree:*)", "Bash(git branch:*)", "Write", "Read", "Edit", "EnterWorktree", "ExitWorktree"]
---

# Worktree DX

Automated git worktree lifecycle with stack detection and self-improvement.

**Announce:** "Using worktree-setup for isolated workspace management."

## How It Works

This plugin provides three things:

1. **PostToolUse hook on EnterWorktree** — auto-runs setup (deps, env sync, package builds)
2. **PreToolUse hook on ExitWorktree** — prompts you to fix any friction encountered
3. **This skill** — for manual setup, troubleshooting, or reviewing worktree health

## Automatic Behavior (hooks handle this)

When `EnterWorktree` is called:
1. The hook checks for a project-local `scripts/setup-worktree.sh` first
2. Falls back to the plugin's stack-aware setup script
3. The script auto-detects the stack and runs appropriate setup

When `ExitWorktree` is called:
1. The hook reminds you to check for friction encountered during the session
2. If friction was found, update the project's `scripts/setup-worktree.sh` to prevent it next time
3. Save a memory note about what was fixed

## Stack Detection

The setup script detects and handles these stacks automatically:

| Lockfile | Tool | Action |
|----------|------|--------|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `bun.lockb` | bun | `bun install --frozen-lockfile` |
| `yarn.lock` | yarn | `yarn install --frozen-lockfile` |
| `package-lock.json` | npm | `npm ci` |
| `uv.lock` | uv | `uv sync` |
| `poetry.lock` | poetry | `poetry install` |
| `Pipfile.lock` | pipenv | `pipenv install --deploy` |
| `requirements.txt` | pip | `pip install -r requirements.txt` |
| `Cargo.lock` | cargo | `cargo fetch` |
| `go.sum` | go | `go mod download` |
| `Gemfile.lock` | bundler | `bundle install` |
| `mix.lock` | mix | `mix deps.get` |

Monorepo build tools:

| Config | Tool | Action |
|--------|------|--------|
| `turbo.json` | Turborepo | `turbo build --filter='./packages/*'` |
| `nx.json` | Nx | `nx run-many --target=build` |
| `lerna.json` | Lerna | `lerna run build` |
| `Cargo.toml` [workspace] | Cargo | `cargo build` |

Env files copied: `.env.local`, `.env`, `.env.development`, `.env.development.local`

## Manual Usage

If the hook didn't fire or you need to re-run setup:

```bash
bash scripts/setup-worktree.sh          # project-local version
# or
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree.sh"  # plugin fallback
```

## Self-Improvement Loop

Every worktree session is an opportunity to improve the next one:

1. **Setup logs timing and status** to `.claude/worktree-setup.log`
2. **On exit**, review whether you hit friction (missing deps, env errors, manual steps)
3. **If yes**: update `scripts/setup-worktree.sh` in the project to handle it
4. **Save a memory note** so the fix persists across conversations

The project-local script always takes priority over the plugin script. This means each project accumulates its own optimizations while the plugin provides a solid baseline for new projects.

## Reviewing Worktree Health

Check the setup log for patterns:

```bash
cat .claude/worktree-setup.log
```

Look for:
- **Increasing durations** — something is getting slower, investigate
- **FAILED entries** — recurring failures need script fixes
- **Steps column** — which steps ran, useful for debugging

## Creating a Project-Local Script

For projects with custom needs, create `scripts/setup-worktree.sh` that extends the plugin's baseline. Copy the plugin script as a starting point:

```bash
cp "${CLAUDE_PLUGIN_ROOT}/scripts/setup-worktree.sh" scripts/setup-worktree.sh
chmod +x scripts/setup-worktree.sh
```

Then customize for your project (e.g., add codegen steps, database migrations, custom build commands).

## Red Flags

**Never:**
- Skip setup and start coding (you'll hit mysterious errors)
- Delete the setup log (it's your improvement data)
- Ignore FAILED entries in the log

**Always:**
- Let the hook run to completion
- Fix friction at exit time, not "later"
- Prefer project-local scripts over plugin defaults for customization
