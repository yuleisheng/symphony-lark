# Logging Best Practices

This guide defines logging conventions for Symphony Lark so Codex can diagnose failures quickly.

## Goals

- Make logs searchable by task and session.
- Capture enough execution context to identify root cause without reruns.
- Keep recurring messages stable.

## Required Context Fields

When logging task-related work, include both identifiers:

- `issue_id`: the Lark task GUID stored in Symphony runtime state
- `issue_identifier`: the synthetic stable display key, for example `LT-1A2B3C4D`

When logging Codex lifecycle events, include:

- `session_id`

## Scope Guidance

- `AgentRunner`: log start, completion, and failure with task context.
- `Orchestrator`: log dispatch, retry, terminal/non-active transitions, and worker exits with task context.
- `Codex.AppServer`: log session start, completion, and error with task context and `session_id`.
