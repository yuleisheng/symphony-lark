---
name: pull
description:
  Sync the current Aident branch or stack with the latest `origin/main`,
  preferring Graphite commands and falling back to Git only when needed.
---

# Pull

## Goals

- Bring trunk and the current working branch up to date.
- Prefer Graphite-native sync commands.
- Resolve conflicts carefully and rerun validation after syncing.

## Steps

1. Ensure the worktree is clean or save the current changes before syncing.
2. If Graphite has not been initialized for the clone, run
   `gt init --trunk main --no-interactive`.
3. Run `gt sync --force --no-interactive`.
4. If the current branch is not `main`, run
   `gt get "$(git branch --show-current)" --downstack --no-interactive`.
5. If Graphite cannot complete the sync after one retry, fall back to Git:
   - `git fetch origin`
   - `git -c merge.conflictstyle=zdiff3 merge origin/main`
6. Resolve conflicts intentionally, stage the resolution, and finish the merge.
7. Rerun the relevant validation for the affected files.
8. Summarize the sync result, notable conflicts, and the resulting `HEAD` SHA.

## Notes

- Prefer Graphite over raw Git, but use Git when Graphite cannot safely finish
  the update.
- Do not rebase interactively unless the task explicitly requires it.
