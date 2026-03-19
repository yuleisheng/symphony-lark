---
name: install-symphony-lark
description: Use when a user wants Codex to clone or update Symphony Lark in an explicit target path, verify the local toolchain and GitHub auth, bootstrap Lark auth and tasklist access, configure the target repo path for task workspaces, and start the local service with WORKFLOW.lark.md.
---

# Install Symphony Lark

## Non-Negotiables

- Always require an explicit target clone path before running any `git` command.
- Run every `git` command only inside that explicit target path.
- If the target path exists but is not the expected repo, stop and ask.
- If the target path exists with local changes, inspect before updating.

## Goals

- Get a local `symphony-lark` checkout built and runnable.
- Verify the required CLIs and auth.
- Prefer app-driven Lark bootstrap when tasklist access is missing.
- Ensure the default workflow can materialize the real repo into each task workspace with a pushable upstream remote.
- Start Symphony with `elixir/WORKFLOW.lark.md`.

## Required Inputs

- target clone path
- repo URL, if the user wants a different fork or remote
- the local repo path Symphony should work on via `SYMPHONY_REPO_ROOT`
- whether the user already has `LARK_APP_ID`, `LARK_APP_SECRET`, and `LARK_TASKLIST_GUID`, or wants the skill to create the tasklist
- the human user's actual Feishu/Lark account email, only when tasklist bootstrap is needed

## Steps

1. Inspect the target path.
   - If missing, clone the repo there.
   - If present, verify it is the expected repo before modifying it.
   - If present and dirty, show branch and status before pulling.
2. Verify tools.
   - `git`
   - `gh`
   - `mise`
   - `codex`
   - `rsync`
   - `command -v codex`
   - `gh auth status`
3. Build Symphony.

```bash
cd <target>/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
```

4. Verify env and auth.
   - `command -v codex`
   - `codex app-server --help`
   - confirm `LARK_APP_ID`
   - confirm `LARK_APP_SECRET`
   - confirm `SYMPHONY_REPO_ROOT` points at the repo the agents should modify
   - confirm `git -C "$SYMPHONY_REPO_ROOT" remote get-url origin` points at the GitHub repo agents should push PRs to
   - if `command -v codex` fails in the same shell that will start Symphony, stop and help the user either add Codex to that shell's `PATH` or set a local `codex.command` override; do not hardcode a machine-specific absolute path into the repo default workflow
   - if `gh auth status` fails, stop and tell the user to log in before continuing
   - if the source repo `origin` is missing or still points at a local filesystem path, stop and fix that remote before continuing because task workspaces inherit it for PR publication
   - if `LARK_TASKLIST_GUID` exists, verify the app can list tasks and custom fields for it
   - if the app cannot read the configured tasklist, continue into API-driven Lark setup
5. Guided Lark setup when needed.
   - create or identify the Lark app in Open Platform
   - confirm the app has the Task and Contact permissions needed to:
     - read and patch tasks
     - list tasklist tasks and custom fields
     - read and create task comments
     - create tasklists
     - add tasklist members
     - create custom fields
   - confirm `contact:user.id:readonly`
   - use the user's actual account email for ID lookup; enterprise email may not return `open_id`
   - prefer API bootstrap over user-selected tasklists:
     - create the tasklist via API
     - look up the user's `open_id` via email
     - add the user as an editor to the app-created tasklist
     - create the `Status` single-select field via API with exact options `Todo`, `In Progress`, `Blocked`, `Input/Feedback Given`, `In Review`, `Done`
     - write back the final `LARK_TASKLIST_GUID`
   - if the tasklist already has a `Status` field, verify it includes every required option; patch or recreate it before continuing
   - if an existing user-owned tasklist is unreadable by the app, stop treating it as the primary path and create an app-owned tasklist instead
6. Start Symphony.

```bash
cd <target>/elixir
export SYMPHONY_REPO_ROOT="<repo-path>"
command -v codex
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  ./WORKFLOW.lark.md
```

Add `--port 4000` if the user wants the dashboard. Start Symphony from the same shell where `command -v codex` succeeds.

7. Smoke test.
   - confirm the service boots
   - confirm the configured workflow loads
   - confirm Symphony can read the configured tasklist
   - confirm the `Status` field is visible to the app
   - confirm the `Status` field options exactly match `Todo`, `In Progress`, `Blocked`, `Input/Feedback Given`, `In Review`, `Done`
   - confirm `gh` can reach GitHub so code-change tasks can publish PRs
   - confirm `git -C "$SYMPHONY_REPO_ROOT" remote get-url origin` is a pushable GitHub remote so new task workspaces inherit the right `origin`

## API Paths

- Tasklist create: `POST /open-apis/task/v2/tasklists`
- User lookup: `POST /open-apis/contact/v3/users/batch_get_id?user_id_type=open_id`
- Add member: `POST /open-apis/task/v2/tasklists/{guid}/add_members?user_id_type=open_id`
- Create `Status`: `POST /open-apis/task/v2/custom_fields?user_id_type=open_id`

## Notes

- Prefer temporary `export` commands unless the user explicitly asks to modify shell startup files.
- `open.larksuite.com` and `open.feishu.cn` may both work in some tenants; keep the workflow endpoint aligned with the base that actually passes the tasklist probes.
- The default workflow expects `SYMPHONY_REPO_ROOT` so each task workspace contains a real repo checkout instead of an empty temp directory, and it inherits the source repo's `origin` remote for PR publication when one exists.
- The supported workflow states are `Todo`, `In Progress`, `Blocked`, `Input/Feedback Given`, `In Review`, and `Done`.
- The lowest-friction path is to let the skill create the tasklist and `Status` field instead of asking the user to find an existing tasklist GUID by hand.
- If blocked, report the exact missing tool, env var, permission, or tasklist/status setup item.
