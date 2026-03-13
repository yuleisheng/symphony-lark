---
name: land
description:
  Land an approved Aident PR through Graphite once checks and review feedback
  are fully clear.
---

# Land

## Goals

- Keep the current stack synced and green.
- Address blocking review feedback before merge.
- Merge with Graphite rather than `gh pr merge`.

## Preconditions

- The current branch has an open PR.
- `gt` and `gh` authentication both work.
- The working tree is clean.

## Steps

1. If the worktree is dirty, use the `commit` skill and then the `push` skill
   before continuing.
2. Run the required validation for the current diff.
3. Use `gh pr view --json number,reviewDecision,mergeable,state,url` to inspect
   the PR.
4. Read unresolved review feedback:
   - `gh pr view --comments`
   - `gh api repos/<owner>/<repo>/pulls/<pr>/comments`
5. If feedback or CI requires changes, address them, rerun validation, and use
   the `push` skill again.
6. If the stack is out of date, run the `pull` skill, rerun validation, and
   submit the updated branch again.
7. Wait for checks with `gh pr checks --watch`.
8. Once human approval is present and checks are green, merge with
   `gt merge --no-interactive`.
9. Confirm the PR is merged and return the Graphite review URL.

## Notes

- Do not call `gh pr merge`.
- If auth is missing for `gt` or `gh`, surface the blocker clearly in the issue
  workpad instead of guessing.
