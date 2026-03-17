---
name: worktree-clean
description: "Find and remove git worktrees whose branches have been merged into main"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/worktree-clean.sh:*)", "Bash(git worktree:*)", "Bash(git branch:*)", "AskUserQuestion"]
---

# Worktree Clean

## Step 1: Scan

Run the clean script in dry-run mode first:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-clean.sh" main
```

## Step 2: Confirm

Show the user what would be removed. If any worktrees have uncommitted changes, warn clearly — those will be skipped.

Ask the user to confirm before removing.

## Step 3: Remove

If confirmed:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-clean.sh" main --force
```

Report what was removed and what was skipped.
