---
name: worktree-log
description: "Show worktree setup timing history and identify performance trends or recurring failures"
allowed-tools: ["Bash(cat:*)", "Bash(grep:*)", "Bash(awk:*)", "Bash(sort:*)", "Bash(wc:*)"]
---

# Worktree Log

Read and analyze `.claude/worktree-setup.log`.

```bash
cat .claude/worktree-setup.log 2>/dev/null || echo "No setup log found."
```

Present:
- **Recent entries** (last 10)
- **Average setup time** across all entries
- **Failure rate** (FAILED count / total)
- **Slowest setup** and what steps it ran
- **Trends** — is setup getting slower or faster over time?

If failures are recurring, suggest checking the setup script for the failing step.
