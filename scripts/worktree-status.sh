#!/usr/bin/env bash
# ABOUTME: Shows all worktrees with their status, merged state, and setup log data.
# ABOUTME: Identifies stale worktrees whose branches have been merged into main.

set -uo pipefail

MAIN_BRANCH="${1:-main}"
LOG_FILE=".claude/worktree-setup.log"

echo "=== Worktrees ==="
echo ""

# Get all worktrees
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    wt_path="${line#worktree }"
  elif [[ "$line" == HEAD\ * ]]; then
    wt_head="${line#HEAD }"
  elif [[ "$line" == branch\ * ]]; then
    wt_branch="${line#branch refs/heads/}"
  elif [[ -z "$line" ]]; then
    # End of worktree entry — print it
    if [ -n "${wt_path:-}" ]; then
      is_main="no"
      if [ "$(git worktree list --porcelain | head -1 | sed 's/^worktree //')" = "$wt_path" ]; then
        is_main="yes"
      fi

      # Check if branch is merged
      merged=""
      if [ "$is_main" = "no" ] && [ -n "${wt_branch:-}" ]; then
        if git merge-base --is-ancestor "${wt_branch}" "origin/${MAIN_BRANCH}" 2>/dev/null; then
          merged=" [MERGED]"
        fi
      fi

      # Check for uncommitted changes
      dirty=""
      if [ -d "$wt_path" ] && [ "$is_main" = "no" ]; then
        if [ -n "$(git -C "$wt_path" status --porcelain 2>/dev/null)" ]; then
          dirty=" [dirty]"
        fi
      fi

      # Get last setup log entry
      last_setup=""
      if [ -f "$LOG_FILE" ] && [ -n "${wt_branch:-}" ]; then
        wt_name=$(basename "$wt_path")
        last_line=$(grep "$wt_name" "$LOG_FILE" 2>/dev/null | tail -1)
        if [ -n "$last_line" ]; then
          last_setup=" — last setup: $(echo "$last_line" | awk -F'|' '{print $3 "|" $4}' | xargs)"
        fi
      fi

      if [ "$is_main" = "yes" ]; then
        printf "  %-50s %s\n" "${wt_branch:-detached} (main)" "${wt_path}"
      else
        printf "  %-50s %s\n" "${wt_branch:-detached}${merged}${dirty}${last_setup}" "${wt_path}"
      fi
    fi
    wt_path="" wt_head="" wt_branch=""
  fi
done < <(git worktree list --porcelain; echo "")

echo ""

# Summary
total=$(git worktree list | wc -l | xargs)
echo "Total: $total worktrees"

# Log summary
if [ -f "$LOG_FILE" ]; then
  echo ""
  echo "=== Recent Setup Log ==="
  echo ""
  tail -10 "$LOG_FILE" | while IFS='|' read -r ts name dur status steps; do
    printf "  %s  %-30s %s  %s\n" "$(echo "$ts" | xargs)" "$(echo "$name" | xargs)" "$(echo "$dur" | xargs)" "$(echo "$status" | xargs)"
  done
  echo ""
  total_setups=$(wc -l < "$LOG_FILE" | xargs)
  failures=$(grep -c "FAILED" "$LOG_FILE" 2>/dev/null || echo "0")
  echo "Total setups: $total_setups ($failures failed)"
fi
