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
  "content": "## Codex Workpad\n- Summary\n- Status\n- Validation\n- Links\n- Risks"
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

## Status Rules

- Use the tasklist `Status` field as the workflow source of truth.
- Move to `In Progress` when active implementation starts.
- Move to `Blocked` only when there is a real external blocker.
- Move to `In Review` when implementation is ready for human review.
- Move to `Done` only after the requested work is complete and verified.
