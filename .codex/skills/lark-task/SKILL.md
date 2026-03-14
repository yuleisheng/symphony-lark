---
name: lark-task
description: Use Symphony's `lark_task_api` dynamic tool to inspect Lark tasks, manage the Codex Workpad comment, and update task status in the configured tasklist.
---

# Lark Task Operations

Use this skill during Symphony app-server sessions when you need to interact with the tracked Lark task.

## Tool

Use the `lark_task_api` dynamic tool. It allows `GET`, `POST`, and `PATCH` requests under `/open-apis/task/v2/*`.

## Common Operations

### Read the current task

- `GET /open-apis/task/v2/tasks/<task_guid>`

### List comments on the task

- `GET /open-apis/task/v2/comments?resource_type=task&resource_id=<task_guid>&page_size=50`

### Create the workpad comment

- `POST /open-apis/task/v2/comments`
- body:

```json
{
  "content": "## Codex Workpad\n- Plan\n- Status\n- Validation\n- Links\n- Risks",
  "resource_type": "task",
  "resource_id": "<task_guid>"
}
```

### Update an existing comment

- `PATCH /open-apis/task/v2/comments/<comment_id>`
- body:

```json
{
  "content": "updated markdown body"
}
```

### Update task status

- `PATCH /open-apis/task/v2/tasks/<task_guid>`
- body:

```json
{
  "update_fields": ["custom_fields"],
  "task": {
    "custom_fields": [
      {
        "guid": "<status-field-guid>",
        "type": "single_select",
        "single_select_value": "<status-option-guid>"
      }
    ]
  }
}
```

- If the patch also updates `completed_at`, include it in `update_fields` as well.

## Workpad Rules

- Keep a single `## Codex Workpad` comment per task.
- If one already exists, update it instead of creating another.
- Use markdown headings and bullet lists.
- Keep it concise and operational.
- Include links such as PRs in the workpad comment instead of scattering status across multiple comments.
- When a task starts from `Todo`, inspect the relevant code first, then update the workpad with a real plan before making code changes.
- The initial plan should contain 2-5 concrete implementation steps, the main files or surfaces to touch, and the validation plan.
- If the task requires code changes, you must use GitHub CLI to publish a PR before finishing. Use `gh` to open the PR; do not stop at a local commit or an unpublished branch.
- If the task becomes blocked, or you cannot publish the required PR, update the workpad with a concise blocker summary, the exact input or approval needed from a human, and the next step once unblocked.
- After you publish a PR with `gh`, update the workpad with `Goal`, `Solution`, `Verification Plan`, and the PR link.

## Status Rules

- Use the tasklist `Status` field as the workflow source of truth.
- Move to `In Progress` when active implementation starts.
- Move to `Blocked` when there is a real external blocker or when the required PR cannot be published, after updating the workpad with the blocker.
- Move to `In Review` only after a PR is published with `gh` and the workpad has been updated with the PR handoff details.
- Move to `Done` only after the requested work is complete and verified with no code changes required, or after the PR-driven review flow has already completed.

## Recommended Comment Shapes

### Initial plan update

```markdown
## Codex Workpad
- Plan:
  - Step 1
  - Step 2
  - Step 3
- Scope:
  - Main files, modules, or surfaces you expect to touch.
- Status: Starting implementation after repo inspection.
- Validation:
  - Commands, tests, or manual checks you plan to run.
- Links:
  - Relevant branch, PR, or task links if any.
- Risks: Known unknowns or `None`.
```

### Blocked update

```markdown
## Codex Workpad
- Plan:
  - Current plan or next intended step.
- Status: Blocked.
- Blocker: <brief blocker summary>
- Needed From Human:
  - Exact approval, information, or credential required.
- Next Step After Input:
  - What you will do once unblocked.
- Links:
  - Relevant task, dependency, or approval links.
```

### PR handoff update

```markdown
## Codex Workpad
- Goal: What problem the task addresses.
- Solution: What changed.
- Verification Plan:
  - What should be checked in review or validation.
- Links:
  - PR URL
  - Any related links
- Risks: Follow-ups, caveats, or `None`.
```
