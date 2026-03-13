# Symphony Elixir

This directory contains the Elixir orchestration service that polls Lark Tasks, creates per-task workspaces, and runs Codex in app-server mode.

## Environment

- Elixir: `1.19.x` via `mise`
- Main quality gate: `make all`

## Conventions

- Runtime config is loaded from `WORKFLOW.lark.md` front matter via `SymphonyElixir.Workflow` and `SymphonyElixir.Config`.
- Keep the implementation structurally close to upstream Symphony where practical.
- Lark-specific code belongs under `lib/symphony_elixir/lark/`.
- Workspace safety is critical:
  - never run Codex turns in the source repo
  - keep workspaces under the configured workspace root
- Follow `docs/logging.md` for required task/session context fields.

## Required Rules

- Public functions in `lib/` must have adjacent `@spec`s.
- Prefer narrowly scoped changes over wide refactors.
- If behavior or config changes, update:
  - `../README.md`
  - `README.md`
  - `WORKFLOW.lark.md`
