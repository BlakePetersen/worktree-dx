#!/usr/bin/env bash
# ABOUTME: Stack-aware worktree setup script for any project.
# ABOUTME: Detects build tools, installs deps, syncs env files, builds packages, runs codegen.

set -uo pipefail

SETUP_START=$(date +%s)
SETUP_STATUS="ok"
STEPS_RUN=""

# Find the main worktree (first listed is always the main one)
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')
CURRENT_DIR=$(pwd)
LOG_DIR="${MAIN_WORKTREE}/.claude"
LOG_FILE="${LOG_DIR}/worktree-setup.log"
CONFIG_FILE=".worktree-dx.json"

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

# --- Config file support ---

config_get() {
  local key="$1"
  local default="${2:-}"
  if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    local val
    val=$(jq -r "$key // empty" "$CONFIG_FILE" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      echo "$val"
      return
    fi
  fi
  echo "$default"
}

config_get_array() {
  local key="$1"
  if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
    jq -r "$key[]? // empty" "$CONFIG_FILE" 2>/dev/null
  fi
}

if [ -f "$CONFIG_FILE" ]; then
  echo "Config: $CONFIG_FILE"
fi
echo ""

# --- Pre-setup hooks from config ---

run_config_hooks() {
  local phase="$1"
  local commands
  commands=$(config_get_array ".$phase")
  if [ -n "$commands" ]; then
    echo "→ Running $phase hooks..."
    while IFS= read -r cmd; do
      echo "  $ $cmd"
      eval "$cmd"
    done <<< "$commands"
    STEPS_RUN="${STEPS_RUN}${phase},"
    echo ""
  fi
}

run_config_hooks "pre_setup"

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

  # PHP
  if [ -f "composer.lock" ]; then
    echo "→ Installing dependencies (composer)..."
    composer install --no-interaction
    STEPS_RUN="${STEPS_RUN}composer,"
  fi

  # .NET
  if compgen -G "*.sln" > /dev/null 2>&1 || compgen -G "*.csproj" > /dev/null 2>&1; then
    echo "→ Restoring dependencies (dotnet)..."
    dotnet restore
    STEPS_RUN="${STEPS_RUN}dotnet,"
  fi
}

detect_and_install_deps
echo ""

# --- Step 2: Copy env files from main worktree ---

echo "→ Syncing env files from main worktree..."
ENV_PATTERNS=".env.local .env .env.development .env.development.local"

# Override env patterns from config if specified
custom_patterns=$(config_get_array ".env_patterns")
if [ -n "$custom_patterns" ]; then
  ENV_PATTERNS="$custom_patterns"
fi

# Build find arguments for env patterns
FIND_ARGS=()
first=true
for pattern in $ENV_PATTERNS; do
  if [ "$first" = true ]; then
    FIND_ARGS+=(-name "$pattern")
    first=false
  else
    FIND_ARGS+=(-o -name "$pattern")
  fi
done

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
done < <(find "$MAIN_WORKTREE" \( "${FIND_ARGS[@]}" \) \
  -not -path "*/node_modules/*" \
  -not -path "*/.claude/*" \
  -not -path "*/.next/*" \
  -not -path "*/target/*" \
  -not -path "*/.venv/*" \
  -not -path "*/vendor/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
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

# --- Step 4: Codegen ---

run_codegen() {
  # Prisma
  if [ -f "prisma/schema.prisma" ] || compgen -G "*/prisma/schema.prisma" > /dev/null 2>&1; then
    echo "→ Generating Prisma client..."
    npx prisma generate 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}prisma,"
  fi

  # Convex
  if [ -d "convex" ] && [ -f "convex/schema.ts" -o -f "convex/schema.js" ]; then
    echo "→ Generating Convex types..."
    npx convex codegen 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}convex,"
  fi

  # GraphQL codegen
  if [ -f "codegen.ts" ] || [ -f "codegen.yml" ] || [ -f "codegen.yaml" ]; then
    echo "→ Running GraphQL codegen..."
    npx graphql-codegen 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}graphql-codegen,"
  fi

  # Protobuf
  if compgen -G "**/*.proto" > /dev/null 2>&1 && [ -f "buf.gen.yaml" ]; then
    echo "→ Generating protobuf types..."
    buf generate 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}protobuf,"
  fi

  # OpenAPI
  if [ -f "openapi-codegen.config.ts" ] || [ -f "orval.config.ts" ]; then
    echo "→ Generating API client types..."
    npx openapi-codegen gen 2>/dev/null || npx orval 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}openapi,"
  fi

  # Rails
  if [ -f "bin/rails" ] && [ -d "db/migrate" ]; then
    echo "→ Running database migrations..."
    bin/rails db:migrate 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}rails-migrate,"
  fi

  # Django
  if [ -f "manage.py" ] && grep -q "django" requirements.txt 2>/dev/null; then
    echo "→ Running Django migrations..."
    python manage.py migrate 2>/dev/null || true
    STEPS_RUN="${STEPS_RUN}django-migrate,"
  fi
}

run_codegen
echo ""

# --- Step 5: Docker services ---

start_docker_services() {
  if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ] || [ -f "compose.yaml" ]; then
    # Only start if docker is available and config asks for it
    local should_start
    should_start=$(config_get ".docker" "false")
    if [ "$should_start" = "true" ] && command -v docker &>/dev/null; then
      echo "→ Starting Docker services..."
      docker compose up -d 2>/dev/null || docker-compose up -d 2>/dev/null || true
      STEPS_RUN="${STEPS_RUN}docker,"
    fi
  fi
}

start_docker_services

# --- Post-setup hooks from config ---

run_config_hooks "post_setup"

ELAPSED=$(($(date +%s) - SETUP_START))
echo "✓ Worktree ready (${ELAPSED}s)"
