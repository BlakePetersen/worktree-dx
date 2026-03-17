# worktree-dx

Stack-aware git worktree automation for [Claude Code](https://claude.com/claude-code). Detects your project's build tools, installs dependencies, syncs environment files, builds shared packages, and runs codegen — automatically on every `EnterWorktree`.

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

## Commands

| Command | Description |
|---------|-------------|
| `/worktree-setup` | Manual setup or troubleshoot the current worktree |
| `/worktree-status` | Show all worktrees with merge state, dirty state, and setup history |
| `/worktree-clean` | Find and remove worktrees whose branches have been merged |
| `/worktree-log` | Analyze setup timing trends, failure rates, and slowest setups |

## What It Does

### On `EnterWorktree` (automatic)

1. **Detects your stack** from lockfiles and config
2. **Runs pre-setup hooks** from `.worktree-dx.json` if present
3. **Installs dependencies** using the correct package manager
4. **Copies env files** from the main worktree
5. **Builds shared packages** if you're in a monorepo
6. **Runs codegen** (Prisma, Convex, GraphQL, Protobuf, OpenAPI)
7. **Runs migrations** (Rails, Django) if detected
8. **Starts Docker services** if configured
9. **Runs post-setup hooks** from `.worktree-dx.json` if present
10. **Logs timing and status** to `.claude/worktree-setup.log`

### On `ExitWorktree` (automatic)

Prompts Claude to reflect on any friction encountered during the session and fix the setup script so it doesn't happen again.

### On Session Start (automatic)

Checks for stale worktrees whose branches have been merged into main and suggests cleanup.

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
| `composer.lock` | composer | `composer install` |
| `*.sln` / `*.csproj` | dotnet | `dotnet restore` |

### Monorepo Build Tools

| Config | Tool | Command |
|--------|------|---------|
| `turbo.json` | Turborepo | `turbo build --filter='./packages/*'` |
| `nx.json` | Nx | `nx run-many --target=build` |
| `lerna.json` | Lerna | `lerna run build` |
| `Cargo.toml` with `[workspace]` | Cargo | `cargo build` |

### Codegen & Migrations

| Detected | Action |
|----------|--------|
| `prisma/schema.prisma` | `npx prisma generate` |
| `convex/schema.ts` | `npx convex codegen` |
| `codegen.ts` / `codegen.yml` | `npx graphql-codegen` |
| `buf.gen.yaml` + `*.proto` | `buf generate` |
| `openapi-codegen.config.ts` | `npx openapi-codegen gen` |
| `bin/rails` + `db/migrate/` | `bin/rails db:migrate` |
| `manage.py` + django | `python manage.py migrate` |

## Project Config (`.worktree-dx.json`)

Drop a `.worktree-dx.json` in your project root to customize setup without writing a full script:

```json
{
  "pre_setup": [
    "docker compose up -d postgres"
  ],
  "post_setup": [
    "npx prisma generate",
    "bin/rails db:seed"
  ],
  "env_patterns": [
    ".env.local",
    ".env.test",
    ".env.development"
  ],
  "docker": true
}
```

| Key | Type | Description |
|-----|------|-------------|
| `pre_setup` | `string[]` | Commands to run before dependency install |
| `post_setup` | `string[]` | Commands to run after all setup steps |
| `env_patterns` | `string[]` | Env file names to copy (overrides defaults) |
| `docker` | `bool` | Start `docker compose up -d` if compose file exists |

## Project-Level Overrides

The plugin checks for `scripts/setup-worktree.sh` in your project first. If found, it runs that instead of the plugin's generic script. This lets you fully customize setup while keeping the plugin as a fallback for projects without one.

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
2026-03-17T14:22:01-07:00 | eng-250/fix-auth | 28s | ok | pnpm,env(7),turbo,convex,
2026-03-17T16:45:33-07:00 | eng-251/new-matching | 3s | ok | pnpm,env(0),turbo,
2026-03-18T09:12:05-07:00 | eng-252/mobile-nav | 4s | FAILED(exit=1) | pnpm,
```

Use `/worktree-log` to analyze trends across all setups.

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
                    ├── .worktree-dx.json? → run pre_setup hooks
                    ├── detect lockfiles → install deps
                    ├── copy .env* from main worktree
                    ├── detect monorepo tool → build packages
                    ├── detect codegen/migrations → run them
                    ├── docker: true? → docker compose up -d
                    ├── .worktree-dx.json? → run post_setup hooks
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

```
SessionStart
    │
    ▼
SessionStart hook fires
    │
    └── Merged worktrees detected? → "Run /worktree-clean"
```

## License

MIT
