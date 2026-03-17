---
name: worktree-status
description: "Show all git worktrees with merge status, uncommitted changes, and setup log history"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/worktree-status.sh:*)", "Bash(git worktree:*)"]
---

# Worktree Status

Run the status script and present the results clearly:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/worktree-status.sh"
```

After running, summarize:
- Total active worktrees
- Any MERGED worktrees that should be cleaned up
- Any dirty worktrees with uncommitted changes
- Recent setup log trends (failures, slow setups)

If merged worktrees exist, suggest running `/worktree:clean`.
