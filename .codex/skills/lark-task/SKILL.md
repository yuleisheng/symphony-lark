---
name: lark-task
description: Use Symphony's `lark_task_api` dynamic tool to inspect Lark tasks, manage the Codex Workpad comment, and update task status in the configured tasklist.
---

# Lark Task Operations

Use this skill during Symphony app-server sessions when you need to interact with the tracked Lark task.

## Tool

Use the `lark_task_api` dynamic tool. It only allows `GET`, `POST`, and `PATCH` requests under `/open-apis/task/v2/*`.

## Common Operations

### Read the current task

- `GET /open-apis/task/v2/tasks/<task_guid>`

### List comments on the task

- `GET /open-apis/task/v2/tasks/<task_guid>/comments`

### Create the workpad comment

- `POST /open-apis/task/v2/tasks/<task_guid>/comments`
- body:

```json
{
  "content": "## Codex Workpad\n- Plan\n- Status\n- Validation\n- Links\n- Risks"
}
```

### Update an existing comment

- `PATCH /open-apis/task/v2/tasks/<task_guid>/comments/<comment_id>`
- body:

```json
{
  "comment": {
    "content": "updated markdown body"
  }
}
```

### Update task status

- `PATCH /open-apis/task/v2/tasks/<task_guid>`
- body:

```json
{
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

## Workpad Rules

- Keep a single `## Codex Workpad` comment per task.
- If one already exists, update it instead of creating another.
- Keep it concise and operational.
- Include links such as PRs in the workpad comment instead of scattering status across multiple comments.
- When a task starts from `Todo`, update the workpad immediately with a short plan before proceeding.
- If the task becomes blocked, update the workpad with a brief blocker summary.
- If you publish a PR, update the workpad with `Issue`, `Solution`, `Verification Plan`, and the PR link.

## Status Rules

- Use the tasklist `Status` field as the workflow source of truth.
- Move to `In Progress` when active implementation starts.
- Move to `Blocked` only when there is a real external blocker, after updating the workpad with the blocker.
- Move to `In Review` after a PR is published and the workpad has been updated with the PR handoff details.
- Move to `Done` only after the requested work is complete and verified.

## Recommended Comment Shapes

### Initial plan update

```markdown
## Codex Workpad
- Plan: 1-3 concrete implementation steps.
- Status: Starting work.
- Validation: How you expect to verify the change.
- Links: Relevant branch, PR, or task links if any.
- Risks: Known unknowns or `None`.
```

### Blocked update

```markdown
## Codex Workpad
- Plan: Current plan or next intended step.
- Status: Blocked on <brief blocker>.
- Validation: What is pending once unblocked.
- Links: Relevant task or dependency links.
- Risks: <brief blocker summary>
```

### PR handoff update

```markdown
## Codex Workpad
- Issue: What problem the task addresses.
- Solution: What changed.
- Verification Plan: What should be checked in review or validation.
- Links: PR URL and any related links.
- Risks: Follow-ups, caveats, or `None`.
```
