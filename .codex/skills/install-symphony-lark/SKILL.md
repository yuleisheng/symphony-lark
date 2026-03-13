---
name: install-symphony-lark
description: Use when a user wants Codex to clone or update Symphony Lark in an explicit target path, verify the local toolchain, guide the Lark Tasks setup, and start the local service with WORKFLOW.lark.md.
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
- Guide the Lark app, tasklist, and `Status` setup if needed.
- Start Symphony with `elixir/WORKFLOW.lark.md`.

## Required Inputs

- target clone path
- repo URL, if the user wants a different fork or remote
- whether the user already has `LARK_APP_ID`, `LARK_APP_SECRET`, and `LARK_TASKLIST_GUID`

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
   - confirm `LARK_TASKLIST_GUID`, or continue into guided Lark setup
5. Guided Lark setup when needed.
   - create or identify the Lark app in Open Platform
   - confirm Task v2 read, patch, tasklist, custom-field, and comment permissions
   - create or choose one shared tasklist for Symphony
   - create a single-select `Status` field with exact options:
     - `Todo`
     - `In Progress`
     - `Blocked`
     - `In Review`
     - `Done`
   - obtain the `tasklist_guid`
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

## Notes

- Prefer temporary `export` commands unless the user explicitly asks to modify shell startup files.
- If blocked, report the exact missing tool, env var, permission, or tasklist/status setup item.
