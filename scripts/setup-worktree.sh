#!/usr/bin/env bash
# ABOUTME: Stack-aware worktree setup script for any project.
# ABOUTME: Detects build tools, installs deps, syncs env files, and builds packages.

set -uo pipefail

SETUP_START=$(date +%s)
SETUP_STATUS="ok"
STEPS_RUN=""

# Find the main worktree (first listed is always the main one)
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
CURRENT_DIR=$(pwd)
LOG_DIR="${MAIN_WORKTREE}/.claude"
LOG_FILE="${LOG_DIR}/worktree-setup.log"

cleanup() {
  local exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    SETUP_STATUS="FAILED(exit=$exit_code)"
  fi
  SETUP_END=$(date +%s)
  DURATION=$((SETUP_END - SETUP_START))
  mkdir -p "$LOG_DIR"
  echo "$(date -Iseconds) | $(basename "${CURRENT_DIR:-.}") | ${DURATION}s | $SETUP_STATUS | ${STEPS_RUN}" >> "$LOG_FILE"
  exit "$exit_code"
}
trap cleanup EXIT

if [ "$MAIN_WORKTREE" = "$CURRENT_DIR" ]; then
  echo "This script is for worktrees, not the main checkout."
  exit 1
fi

echo "Setting up worktree: $(basename "$CURRENT_DIR")"
echo "Main worktree: $MAIN_WORKTREE"
echo ""

# --- Step 1: Install dependencies based on detected stack ---

detect_and_install_deps() {
  # Node.js — detect package manager
  if [ -f "pnpm-lock.yaml" ]; then
    echo "→ Installing dependencies (pnpm)..."
    pnpm install --frozen-lockfile
    STEPS_RUN="${STEPS_RUN}pnpm,"
  elif [ -f "bun.lockb" ] || [ -f "bun.lock" ]; then
    echo "→ Installing dependencies (bun)..."
    bun install --frozen-lockfile
    STEPS_RUN="${STEPS_RUN}bun,"
  elif [ -f "yarn.lock" ]; then
    echo "→ Installing dependencies (yarn)..."
    yarn install --frozen-lockfile
    STEPS_RUN="${STEPS_RUN}yarn,"
  elif [ -f "package-lock.json" ]; then
    echo "→ Installing dependencies (npm)..."
    npm ci
    STEPS_RUN="${STEPS_RUN}npm,"
  elif [ -f "package.json" ]; then
    echo "→ Installing dependencies (npm — no lockfile found)..."
    npm install
    STEPS_RUN="${STEPS_RUN}npm,"
  fi

  # Python
  if [ -f "uv.lock" ]; then
    echo "→ Installing dependencies (uv)..."
    uv sync
    STEPS_RUN="${STEPS_RUN}uv,"
  elif [ -f "poetry.lock" ]; then
    echo "→ Installing dependencies (poetry)..."
    poetry install
    STEPS_RUN="${STEPS_RUN}poetry,"
  elif [ -f "Pipfile.lock" ]; then
    echo "→ Installing dependencies (pipenv)..."
    pipenv install --deploy
    STEPS_RUN="${STEPS_RUN}pipenv,"
  elif [ -f "requirements.txt" ]; then
    echo "→ Installing dependencies (pip)..."
    pip install -r requirements.txt
    STEPS_RUN="${STEPS_RUN}pip,"
  fi

  # Rust
  if [ -f "Cargo.lock" ]; then
    echo "→ Fetching dependencies (cargo)..."
    cargo fetch
    STEPS_RUN="${STEPS_RUN}cargo,"
  fi

  # Go
  if [ -f "go.sum" ]; then
    echo "→ Downloading dependencies (go)..."
    go mod download
    STEPS_RUN="${STEPS_RUN}go,"
  fi

  # Ruby
  if [ -f "Gemfile.lock" ]; then
    echo "→ Installing dependencies (bundler)..."
    bundle install
    STEPS_RUN="${STEPS_RUN}bundler,"
  fi

  # Elixir
  if [ -f "mix.lock" ]; then
    echo "→ Installing dependencies (mix)..."
    mix deps.get
    STEPS_RUN="${STEPS_RUN}mix,"
  fi
}

detect_and_install_deps
echo ""

# --- Step 2: Copy env files from main worktree ---

echo "→ Syncing env files from main worktree..."
ENV_COUNT=0
while IFS= read -r -d '' env_file; do
  relative="${env_file#$MAIN_WORKTREE/}"
  target_dir=$(dirname "$relative")
  mkdir -p "$target_dir"
  if [ ! -f "$relative" ]; then
    cp "$env_file" "$relative"
    echo "  Copied $relative"
    ((ENV_COUNT++)) || true
  fi
done < <(find "$MAIN_WORKTREE" \( -name ".env.local" -o -name ".env" -o -name ".env.development" -o -name ".env.development.local" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.claude/*" \
  -not -path "*/.next/*" \
  -not -path "*/target/*" \
  -not -path "*/.venv/*" \
  -not -path "*/vendor/*" \
  -print0)

if [ "$ENV_COUNT" -eq 0 ]; then
  echo "  No new env files to copy"
fi
STEPS_RUN="${STEPS_RUN}env(${ENV_COUNT}),"
echo ""

# --- Step 3: Build shared packages (monorepo only) ---

build_monorepo_packages() {
  # Turborepo
  if [ -f "turbo.json" ]; then
    echo "→ Building shared packages (turbo)..."
    if command -v pnpm &>/dev/null && [ -f "pnpm-lock.yaml" ]; then
      pnpm turbo build --filter='./packages/*'
    elif command -v npx &>/dev/null; then
      npx turbo build --filter='./packages/*'
    fi
    STEPS_RUN="${STEPS_RUN}turbo,"
    return
  fi

  # Nx
  if [ -f "nx.json" ]; then
    echo "→ Building affected packages (nx)..."
    npx nx run-many --target=build --projects='packages/*'
    STEPS_RUN="${STEPS_RUN}nx,"
    return
  fi

  # Lerna
  if [ -f "lerna.json" ]; then
    echo "→ Building packages (lerna)..."
    npx lerna run build --scope='packages/*'
    STEPS_RUN="${STEPS_RUN}lerna,"
    return
  fi

  # Cargo workspace
  if [ -f "Cargo.toml" ] && grep -q '\[workspace\]' Cargo.toml 2>/dev/null; then
    echo "→ Building workspace (cargo)..."
    cargo build
    STEPS_RUN="${STEPS_RUN}cargo-workspace,"
    return
  fi
}

build_monorepo_packages
echo ""

ELAPSED=$(($(date +%s) - SETUP_START))
echo "✓ Worktree ready (${ELAPSED}s)"
