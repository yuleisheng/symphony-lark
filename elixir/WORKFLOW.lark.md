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
  review_state: "In Review"
  done_state: "Done"
  active_states: ["Todo", "In Progress", "Blocked", "In Review"]
  terminal_states: ["Done"]
  complete_terminal_tasks: true
polling:
  interval_ms: 5000
workspace:
  root: $SYMPHONY_WORKSPACE_ROOT
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: "codex app-server"
---

You are working on the Lark task `{{ task.identifier }}`.

Title: {{ task.title }}

Description:
{% if task.description %}
{{ task.description }}
{% else %}
No description provided.
{% endif %}

Rules:

1. Use the repo-local `lark-task` skill for task comments and status changes.
2. Keep one `## Codex Workpad` comment on the task as the durable status record.
3. Treat `Status` as the workflow source of truth.
4. When you start a task that was in `Todo`, create or update the workpad comment with a brief implementation plan before you proceed.
5. Move the task to `In Progress` once work has actually started.
6. If you hit a real blocker, update the workpad comment with a brief blocker summary and move the task to `Blocked`.
7. If you publish a PR with git or gh, update the workpad comment with `Issue`, `Solution`, `Verification Plan`, and the PR link, then move the task to `In Review`.
8. Move the task to `Done` only when the requested work is complete and verified.
9. When you create or update the workpad comment, keep it concise and operational:

## Codex Workpad
- Plan
- Status
- Validation
- Links
- Risks

10. Reuse the current workspace state on continuation turns. Do not restate prior context before acting.
