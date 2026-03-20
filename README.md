# Symphony Lark

Symphony Lark is a Lark Tasks fork of [OpenAI Symphony](https://github.com/openai/symphony). The fork stays structurally close to upstream so upstream changes stay easier to merge, but every agent-visible surface in this repo is Lark-only.

[![Symphony demo video preview](.github/media/symphony-demo-poster.jpg)](.github/media/symphony-demo.mp4)

> [!WARNING]
> Symphony has not been optimized for token consumption yet. Watch your token usage and cost closely while using it.
> [`elixir/WORKFLOW.lark.md`](elixir/WORKFLOW.lark.md) is the main place to reduce token consumption. If you find prompt or workflow changes that cut tokens without hurting behavior, feel free to submit a PR.

## What Changed

- Lark Tasks replaces Linear as the only supported tracker.
- The default workflow file is [`elixir/WORKFLOW.lark.md`](elixir/WORKFLOW.lark.md).
- The repo-local install entrypoint is `install-symphony-lark`.
- Repo-local Linear skills, prompts, and workflow examples are removed so Codex does not spend runtime context on unused tracker logic.

## Fastest Setup

Use the repo-local install skill:

> Use `install-symphony-lark` to clone this repo into `/path/to/symphony-lark`, verify the toolchain, guide the Lark setup, and start Symphony with `elixir/WORKFLOW.lark.md`.

The skill requires an explicit clone path. All `git` commands should run only inside that checkout.

## Install The Skill Globally

If you want to reuse the install skill from other repos, use Codex's built-in `skill-installer`:

> Install the skill from `yuleisheng/symphony-lark` at path `.codex/skills/install-symphony-lark`

Then restart Codex and invoke it with:

> Use `install-symphony-lark` to set up Symphony Lark on this machine.

## Manual Setup

The full manual path lives in [`elixir/README.md`](elixir/README.md). It covers:

- required env vars
- how to create the Lark app and grant the required read/write permissions
- how to bootstrap an app-owned or shared tasklist and the `Status` field
- how `LARK_TASKLIST_GUID` is created or discovered
- how to set `SYMPHONY_REPO_ROOT` and verify GitHub auth
- the default 5 second polling interval
- how to run Symphony with `WORKFLOW.lark.md`
- an optional advanced local reusable-worktree pool for fixed permanent worktrees

## Agent Status Flow

Symphony treats the tasklist-scoped `Status` field as the workflow source of truth.

- `Todo`: runnable. The agent reads the task, inspects the repo, posts a plan comment, and Symphony moves the task to `In Progress` when dispatch starts.
- `In Progress`: runnable. The agent is actively implementing or validating work.
- `Blocked`: not runnable. The agent moves the task here when it cannot continue and adds a concise blocker comment with the exact human input needed.
- `Input/Feedback Given`: runnable. A human uses this to re-queue a blocked task or PR feedback. Symphony injects the latest task comment into the next run, then moves the task back to `In Progress`.
- `In Review`: not runnable. The agent moves the task here after publishing a PR, adding a handoff comment with `Goal`, `Solution`, `Verification Plan`, and the PR link.
- `Done`: terminal. The agent moves the task here only when the requested work is complete. If the task involved code changes, the expected path is PR first, then `In Review`, then `Done`.

The fuller workflow contract lives in [`elixir/README.md`](elixir/README.md#agent-status-behavior).

## Upstream Sync

This fork is intentionally Lark-only at the product surface, but the internal layout stays close to upstream Symphony. Keep upstream syncs small and regular, and keep Lark-specific changes grouped in:

- `elixir/lib/symphony_elixir/lark`
- `elixir/lib/symphony_elixir/codex/dynamic_tool.ex`
- `elixir/WORKFLOW.lark.md`
- `.codex/skills/install-symphony-lark`
- `.codex/skills/lark-task`

## License

This project is licensed under the [Apache License 2.0](LICENSE).
