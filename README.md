# worktree-dx

Stack-aware git worktree automation for [Claude Code](https://claude.com/claude-code). Detects your project's build tools, installs dependencies, syncs environment files, and builds shared packages — automatically on every `EnterWorktree`.

## Why

Spinning up a git worktree in a real project means repeating the same manual steps: install deps, copy env files, build shared packages, hope you didn't forget anything. Multiply that by every branch, every day, and it's death by a thousand paper cuts.

worktree-dx eliminates this by hooking into Claude Code's worktree lifecycle. It detects your stack, runs the right setup, and gets out of the way. And it gets better over time — every worktree session is an opportunity to improve the next one.

## Install

Add to your `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "worktree-dx@worktree-dx": true
  },
  "extraKnownMarketplaces": {
    "worktree-dx": {
      "source": {
        "source": "github",
        "repo": "BlakePetersen/worktree-dx"
      }
    }
  }
}
```

## What It Does

### On `EnterWorktree` (automatic)

1. **Detects your stack** from lockfiles and config
2. **Installs dependencies** using the correct package manager
3. **Copies env files** (`.env.local`, `.env`, `.env.development`) from the main worktree
4. **Builds shared packages** if you're in a monorepo
5. **Logs timing and status** to `.claude/worktree-setup.log`

### On `ExitWorktree` (automatic)

Prompts Claude to reflect on any friction encountered during the session and fix the setup script so it doesn't happen again.

## Supported Stacks

### Dependency Managers

| Lockfile | Tool | Command |
|----------|------|---------|
| `pnpm-lock.yaml` | pnpm | `pnpm install --frozen-lockfile` |
| `bun.lockb` / `bun.lock` | bun | `bun install --frozen-lockfile` |
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

### Monorepo Build Tools

| Config | Tool | Command |
|--------|------|---------|
| `turbo.json` | Turborepo | `turbo build --filter='./packages/*'` |
| `nx.json` | Nx | `nx run-many --target=build` |
| `lerna.json` | Lerna | `lerna run build` |
| `Cargo.toml` with `[workspace]` | Cargo | `cargo build` |

## Project-Level Overrides

The plugin checks for `scripts/setup-worktree.sh` in your project first. If found, it runs that instead of the plugin's generic script. This lets you add project-specific steps (codegen, database migrations, custom build commands) while keeping the plugin as a fallback for projects without one.

To create a project-local script from the plugin's template:

```bash
cp ~/.claude/plugins/local/worktree-dx/scripts/setup-worktree.sh scripts/setup-worktree.sh
chmod +x scripts/setup-worktree.sh
# customize as needed
```

## Self-Improvement

worktree-dx is designed to get better over time:

1. **Every setup logs timing and status** to `.claude/worktree-setup.log`
2. **On exit**, Claude is prompted to fix any friction encountered
3. **Fixes go into the project-local script**, so they persist
4. **Memory notes** carry lessons across conversations

Example log:

```
2026-03-17T14:22:01-07:00 | eng-250/fix-auth | 28s | ok | pnpm,env(7),turbo,
2026-03-17T16:45:33-07:00 | eng-251/new-matching | 3s | ok | pnpm,env(0),turbo,
2026-03-18T09:12:05-07:00 | eng-252/mobile-nav | 4s | FAILED(exit=1) | pnpm,
```

## How It Works

```
EnterWorktree
    │
    ▼
PostToolUse hook fires
    │
    ├── scripts/setup-worktree.sh exists? ──yes──▶ run project script
    │
    └── no ──▶ run plugin script
                    │
                    ├── detect lockfiles → install deps
                    ├── copy .env* from main worktree
                    ├── detect monorepo tool → build packages
                    └── log timing + status
```

```
ExitWorktree
    │
    ▼
PreToolUse hook fires
    │
    └── "Did you hit friction? Fix the setup script."
         │
         ├── Update scripts/setup-worktree.sh
         └── Save memory note
```

## License

MIT
