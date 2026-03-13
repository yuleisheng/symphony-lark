---
name: install-symphony-lark
description: Use when a user wants Codex to clone or update Symphony Lark in an explicit target path, verify the local toolchain, bootstrap Lark auth and tasklist access, and start the local service with WORKFLOW.lark.md.
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
- Start Symphony with `elixir/WORKFLOW.lark.md`.

## Required Inputs

- target clone path
- repo URL, if the user wants a different fork or remote
- whether the user already has `LARK_APP_ID`, `LARK_APP_SECRET`, and `LARK_TASKLIST_GUID`
- the human user's actual Feishu/Lark account email when tasklist bootstrap is needed

## Steps

1. Inspect the target path.
   - If missing, clone the repo there.
   - If present, verify it is the expected repo before modifying it.
   - If present and dirty, show branch and status before pulling.
2. Verify tools.
   - `git`
   - `mise`
   - `codex`
3. Build Symphony.

```bash
cd <target>/elixir
mise trust
mise install
mise exec -- mix setup
mise exec -- mix build
```

4. Verify env and auth.
   - `codex app-server --help`
   - confirm `LARK_APP_ID`
   - confirm `LARK_APP_SECRET`
   - if `LARK_TASKLIST_GUID` exists, verify the app can list tasks and custom fields for it
   - if the app cannot read the configured tasklist, continue into API-driven Lark setup
5. Guided Lark setup when needed.
   - create or identify the Lark app in Open Platform
   - confirm Task v2 read, patch, tasklist, custom-field, and comment permissions
   - confirm `contact:user.id:readonly`
   - use the user's actual account email for ID lookup; enterprise email may not return `open_id`
   - prefer API bootstrap over user-selected tasklists:
     - create the tasklist via API
     - look up the user's `open_id` via email
     - add the user as an editor to the app-created tasklist
     - create the `Status` single-select field via API with exact options `Todo`, `In Progress`, `Blocked`, `In Review`, `Done`
     - write back the final `LARK_TASKLIST_GUID`
   - if an existing user-owned tasklist is unreadable by the app, stop treating it as the primary path and create an app-owned tasklist instead
6. Start Symphony.

```bash
cd <target>/elixir
mise exec -- ./bin/symphony \
  --i-understand-that-this-will-be-running-without-the-usual-guardrails \
  ./WORKFLOW.lark.md
```

Add `--port 4000` if the user wants the dashboard.

7. Smoke test.
   - confirm the service boots
   - confirm the configured workflow loads
   - confirm Symphony can read the configured tasklist
   - confirm the `Status` field is visible to the app

## API Paths

- Tasklist create: `POST /open-apis/task/v2/tasklists`
- User lookup: `POST /open-apis/contact/v3/users/batch_get_id?user_id_type=open_id`
- Add member: `POST /open-apis/task/v2/tasklists/{guid}/add_members?user_id_type=open_id`
- Create `Status`: `POST /open-apis/task/v2/custom_fields?user_id_type=open_id`

## Notes

- Prefer temporary `export` commands unless the user explicitly asks to modify shell startup files.
- `open.larksuite.com` and `open.feishu.cn` may both work in some tenants; keep the workflow endpoint aligned with the base that actually passes the tasklist probes.
- If blocked, report the exact missing tool, env var, permission, or tasklist/status setup item.
