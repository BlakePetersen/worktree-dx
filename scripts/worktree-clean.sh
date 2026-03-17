#!/usr/bin/env bash
# ABOUTME: Finds worktrees whose branches have been merged and lists them for cleanup.
# ABOUTME: With --force flag, removes them automatically.

set -uo pipefail

MAIN_BRANCH="${1:-main}"
FORCE="${2:-}"
MAIN_WORKTREE=$(git worktree list --porcelain | head -1 | sed 's/^worktree //')

echo "Scanning for merged worktrees..."
echo ""

STALE=()
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    wt_path="${line#worktree }"
  elif [[ "$line" == branch\ * ]]; then
    wt_branch="${line#branch refs/heads/}"
  elif [[ -z "$line" ]]; then
    if [ -n "${wt_path:-}" ] && [ "$wt_path" != "$MAIN_WORKTREE" ] && [ -n "${wt_branch:-}" ]; then
      if git merge-base --is-ancestor "${wt_branch}" "origin/${MAIN_BRANCH}" 2>/dev/null; then
        dirty=""
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
          dirty=" (has uncommitted changes!)"
        fi
        echo "  MERGED: ${wt_branch}${dirty}"
        echo "          ${wt_path}"
        STALE+=("$wt_path|$wt_branch|$dirty")
      fi
    fi
    wt_path="" wt_branch=""
  fi
done < <(git worktree list --porcelain; echo "")

if [ ${#STALE[@]} -eq 0 ]; then
  echo "No stale worktrees found."
  exit 0
fi

echo ""
echo "Found ${#STALE[@]} merged worktree(s)."

if [ "$FORCE" = "--force" ]; then
  for entry in "${STALE[@]}"; do
    IFS='|' read -r path branch dirty <<< "$entry"
    if [ -n "$dirty" ]; then
      echo "SKIPPED $branch — has uncommitted changes"
      continue
    fi
    echo "Removing $branch..."
    git worktree remove "$path" 2>/dev/null && git branch -d "$branch" 2>/dev/null
  done
  echo "Done."
else
  echo "Run with --force to remove them (skips dirty worktrees)."
fi
