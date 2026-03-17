# worktree-dx

Stack-aware git worktree automation for Claude Code. Detects your project's build tools, installs dependencies, syncs environment files, and builds shared packages — automatically on every `EnterWorktree`.

## Components

- **Hooks**: Auto-setup on `EnterWorktree`, self-improvement prompt on `ExitWorktree`
- **Skill**: `worktree-setup` for manual control, troubleshooting, and health review
- **Script**: `scripts/setup-worktree.sh` — stack-aware setup with timing/error logging

## Supported Stacks

Node.js (pnpm, yarn, npm, bun), Python (uv, poetry, pipenv, pip), Rust (cargo), Go, Ruby (bundler), Elixir (mix). Monorepo tools: Turborepo, Nx, Lerna, Cargo workspaces.

## Self-Improvement

Each worktree session logs timing and status. On exit, Claude is prompted to fix any friction by updating the project's local setup script. Projects accumulate optimizations over time.
