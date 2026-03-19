---
tracker:
  endpoint: "https://open.larksuite.com"
  app_id: $LARK_APP_ID
  app_secret: $LARK_APP_SECRET
  tasklist_guid: $LARK_TASKLIST_GUID
  state_field_name: "Status"
  todo_state: "Todo"
  in_progress_state: "In Progress"
  blocked_state: "Blocked"
  feedback_state: "Input/Feedback Given"
  review_state: "In Review"
  done_state: "Done"
  active_states: ["Todo", "In Progress", "Input/Feedback Given"]
  terminal_states: ["Done"]
  complete_terminal_tasks: true
polling:
  interval_ms: 5000
hooks:
  after_create: "test -n \"$SYMPHONY_REPO_ROOT\" || { echo \"SYMPHONY_REPO_ROOT is required\"; exit 1; }; command -v rsync >/dev/null || { echo \"rsync is required\"; exit 1; }; source_origin=\"$(git -C \"$SYMPHONY_REPO_ROOT\" remote get-url origin 2>/dev/null || true)\"; source_origin_push=\"$(git -C \"$SYMPHONY_REPO_ROOT\" remote get-url --push origin 2>/dev/null || true)\"; git clone --local \"$SYMPHONY_REPO_ROOT\" . && if [ -n \"$source_origin\" ]; then git remote set-url origin \"$source_origin\"; fi && if [ -n \"$source_origin_push\" ]; then git remote set-url --push origin \"$source_origin_push\"; fi && rsync -a --delete --exclude '.git' \"$SYMPHONY_REPO_ROOT\"/ ./"
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: "codex app-server"
---

You are working on the Lark task `{{ task.identifier }}`.

Task GUID: `{{ task.id }}`

Title: {{ task.title }}

Description:
{% if task.description %}
{{ task.description }}
{% else %}
No description provided.
{% endif %}

{% if task.resume_comment_required %}
This task was resumed from `Input/Feedback Given`. Read the latest human input or review feedback below before you act.

Latest task comment:
{% if task.latest_comment %}
{{ task.latest_comment }}
{% else %}
No latest task comment was available in the prompt. Use the Lark task API to fetch the latest comment before acting. If you still cannot read it, move the task to `Blocked` with a concise explanation.
{% endif %}
{% endif %}

Rules:

1. Use the built-in Lark task API tool for task comments and status changes. All `lark_task_api.path` values must use the full `/open-apis/task/v2/...` prefix. Do not use relative paths like `tasks/...` or `comments`. When an API path needs the task GUID, use `{{ task.id }}`. Never use `{{ task.identifier }}` as the task GUID.
2. Keep one `## Codex Workpad` comment on the task as the durable status record.
3. Treat `Status` as the workflow source of truth.
4. When a task starts from `Todo`, inspect the relevant code and files first. Do not leave a placeholder comment.
5. After that initial code inspection, create or update the workpad comment in markdown with a clear plan containing 2-5 concrete steps, the main files or surfaces you expect to touch, and the validation you plan to run.
6. Move the task to `In Progress` once active implementation has actually started.
7. If a task starts in `Input/Feedback Given`, treat the latest task comment as required context. Explain in the refreshed workpad plan how you are addressing that specific input or review feedback before you continue implementation.
8. If the task requires code changes, you must use GitHub CLI to publish a PR before you finish. Use `gh` to open the PR; do not stop at a local commit or an unpublished branch.
9. If you are blocked on approval, missing information, missing credentials, an external dependency, or you cannot publish the required PR, update the workpad comment with a concise blocker summary, the exact human input or approval needed, and the next step once unblocked. Then move the task to `Blocked` and stop.
10. After a PR is published with `gh`, update the workpad comment with `Goal`, `Solution`, `Verification Plan`, and the PR link, then move the task to `In Review`.
11. Move the task to `Done` only when the requested work is complete and verified with no code changes required, or after the PR-driven review flow has already happened.
12. When you create or update the workpad comment, use markdown headings and bullet lists. Keep it concise and operational:

## Codex Workpad
- Plan
- Status
- Validation
- Links
- Risks

Lark Task API quick reference:

- Use exact Task v2 paths under `/open-apis/task/v2/...`; do not omit that prefix.
- Use `{{ task.id }}` anywhere the examples below refer to the task GUID.
- Read the current task: `GET /open-apis/task/v2/tasks/{{ task.id }}`
- List task comments: `GET /open-apis/task/v2/comments?resource_type=task&resource_id={{ task.id }}&page_size=50`
- Create task comment: `POST /open-apis/task/v2/comments`
- Create body:

```json
{
  "content": "## Codex Workpad\n- Plan\n- Status\n- Validation\n- Links\n- Risks",
  "resource_type": "task",
  "resource_id": "{{ task.id }}"
}
```

- Update task comment: `PATCH /open-apis/task/v2/comments/<comment_id>`
- Update comment body:

```json
{
  "comment": {
    "content": "updated markdown body"
  },
  "update_fields": ["content"]
}
```

- Update task status: `PATCH /open-apis/task/v2/tasks/{{ task.id }}`
- Do not send `{"task":{"status":"in_progress"}}`. In Task v2, the workflow `Status` field must be updated through `task.custom_fields`.
- Status update body:

```json
{
  "task": {
    "custom_fields": [
      {
        "guid": "<status_field_guid>",
        "type": "single_select",
        "single_select_value": "<option_guid_for_target_state>"
      }
    ]
  },
  "update_fields": ["custom_fields"]
}
```

- Find `<status_field_guid>` and the option GUIDs from the task's `custom_fields` and the matching `/open-apis/task/v2/custom_fields/...` metadata before patching.
- When patching task fields, always include `update_fields`.

13. Reuse the current workspace state on continuation turns. Do not restate prior context before acting.
