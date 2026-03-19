# Symphony Elixir For Lark Tasks

This directory contains the Elixir/OTP implementation of Symphony for Lark Tasks. It polls one Lark tasklist, creates a workspace per task, runs Codex in app-server mode, keeps a workpad comment on the task, and advances task status through a tasklist-scoped `Status` field.

## Preferred Setup Path

Use the repo-local skill from the repository root:

> Use `install-symphony-lark` to set up Symphony Lark on this machine.

The skill is the supported onboarding path. It requires an explicit target clone path, handles the build, and guides the Lark app and tasklist setup.

## Prerequisites

- `mise`
- `codex`
- `gh`
- `rsync`
- a Lark app with Task API access
- `LARK_APP_ID`
- `LARK_APP_SECRET`
- an app-readable Lark tasklist for Symphony, or permission to let the install skill create one
- `LARK_TASKLIST_GUID` after bootstrap
- `SYMPHONY_REPO_ROOT`

## Manual Lark Setup

### 1. Create the Lark app

Create an app in [Lark Open Platform](https://open.larksuite.com/). Use app credentials, not a personal token.

### 2. Grant Task permissions

Grant the Task v2 permissions used by this fork. At minimum, the app needs access to:

- read tasks
- patch tasks
- list tasklist tasks
- list tasklist custom fields
- read task comments
- create task comments
- create tasklists
- add tasklist members
- create custom fields
- `contact:user.id:readonly`

### 3. Create the Symphony tasklist

The lowest-friction path is to let `install-symphony-lark` create an app-owned tasklist, share it back to the human user, and write the resulting `LARK_TASKLIST_GUID`. If you are doing this manually, create or choose one tasklist dedicated to Symphony runs and make sure the app can read it.

### 4. Add the `Status` field

Create a tasklist-scoped single-select custom field named `Status` with these exact options:

- `Todo`
- `In Progress`
- `Blocked`
- `Input/Feedback Given`
- `In Review`
- `Done`

The default workflow expects those exact names.

### 5. Get the tasklist GUID

The supported path is to use `install-symphony-lark`, which can usually create the tasklist and write `LARK_TASKLIST_GUID` for you. If you need the manual fallback, use the Lark Task v2 API and inspect the tasklist object you plan to automate.

Set:

```bash
export LARK_TASKLIST_GUID="<tasklist-guid>"
```

## Workflow File

The default file is [`WORKFLOW.lark.md`](./WORKFLOW.lark.md). Symphony defaults to that filename when no workflow path is passed.

Minimal tracker config:

```yaml
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
codex:
  command: codex app-server
```

Notes:

- `tracker.app_id` falls back to `LARK_APP_ID`.
- `tracker.app_secret` falls back to `LARK_APP_SECRET`.
- `tracker.tasklist_guid` falls back to `LARK_TASKLIST_GUID`.
- `workspace.root` has an internal default. You only need to override it if you want task workspaces somewhere specific.
- `SYMPHONY_REPO_ROOT` is required by the default `hooks.after_create` so each task workspace contains a real repo checkout.
- The default workflow polls every 5 seconds unless `polling.interval_ms` is overridden.
- For local runs, simple `codex.command` values like `codex app-server` are resolved from the Symphony process `PATH`. If your Codex install lives outside `PATH`, either start Symphony with the right `PATH` or set `codex.command` to an absolute path.
- Moving a task into a terminal state also sets `completed_at` when `complete_terminal_tasks` is `true`.
- The workflow prompt should use `task.*` variables. `issue.*` is still available as a compatibility alias, but new workflows should use `task`.
- The intended workflow states are `Todo`, `In Progress`, `Blocked`, `Input/Feedback Given`, `In Review`, and `Done`.

### Agent Status Behavior

Symphony treats the tasklist-scoped `Status` custom field as the workflow source of truth.

- `Todo`: runnable. The agent reads the task description, inspects the repo, writes or refreshes the `## Codex Workpad` plan comment, and Symphony moves the task to `In Progress` when the task is dispatched.
- `In Progress`: runnable. The agent is actively implementing or validating work. Symphony keeps the task in this state while continuation turns are still needed.
- `Blocked`: not runnable. The agent sets this when it cannot continue because of missing input, approval, credentials, an external dependency, or inability to publish the required PR. Before moving to `Blocked`, the agent updates the workpad comment with the blocker, the exact human input needed, and the next step once unblocked.
- `Input/Feedback Given`: runnable. A human uses this to re-queue work after answering a blocker or leaving PR feedback. On pickup, Symphony injects the latest task comment into the first-turn prompt, and then moves the task back to `In Progress`.
- `In Review`: not runnable. The agent sets this after publishing a PR and updating the workpad comment with `Goal`, `Solution`, `Verification Plan`, and the PR link.
- `Done`: terminal. The agent sets this only when the requested work is complete and verified with no code changes required, or after the PR-driven review flow has already happened. When `complete_terminal_tasks` is `true`, Symphony also sets `completed_at`.

### Real Repo Workspaces

`workspace.root` is the parent directory for per-task workspaces, not the repo checkout itself. The default workflow uses Symphony's built-in workspace root and materializes your repo into each fresh task workspace with `hooks.after_create`, so the only required extra env var is `SYMPHONY_REPO_ROOT`.

Example:

```yaml
hooks:
  after_create: "test -n \"$SYMPHONY_REPO_ROOT\" || { echo \"SYMPHONY_REPO_ROOT is required\"; exit 1; }; command -v rsync >/dev/null || { echo \"rsync is required\"; exit 1; }; git clone --local \"$SYMPHONY_REPO_ROOT\" . && rsync -a --delete --exclude '.git' \"$SYMPHONY_REPO_ROOT\"/ ./"
```

Required env:

```bash
export SYMPHONY_REPO_ROOT="/absolute/path/to/your/repo"
```

## Build

```bash
cd elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
```

## Run

```bash
cd elixir
command -v codex
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  ./WORKFLOW.lark.md
```

Add `--port 4000` if you want the dashboard. `command -v codex` should succeed in the same shell you use to launch Symphony.

## Task GUID Troubleshooting

Most users should not need raw task GUIDs outside debugging. If you do need one:

1. List tasks in the configured tasklist with the Task v2 API.
2. Inspect the `guid` of the task you want.
3. Use that GUID with `/open-apis/task/v2/tasks/{task_guid}` for deeper inspection.

The repo-local [`lark-task`](../.codex/skills/lark-task/SKILL.md) skill is the intended agent-side helper for this flow.

## Project Layout

- `lib/`: application code
- `test/`: ExUnit coverage
- `WORKFLOW.lark.md`: default workflow contract
- `../.codex/skills/install-symphony-lark/`: guided install flow
- `../.codex/skills/lark-task/`: agent-side task operations

## Testing

```bash
make all
```
