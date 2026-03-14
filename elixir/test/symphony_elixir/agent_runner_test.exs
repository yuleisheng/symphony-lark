defmodule SymphonyElixir.AgentRunnerTest do
  use SymphonyElixir.TestSupport

  test "agent runner injects the latest feedback comment into the first prompt" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-feedback-prompt-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      input_log = Path.join(test_root, "input.log")

      File.mkdir_p!(workspace_root)
      File.write!(input_log, "")

      File.write!(codex_binary, """
      #!/bin/sh
      input_log="#{input_log}"
      count=0
      while IFS= read -r line; do
        printf '%s\n' "$line" >> "$input_log"
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-feedback-prompt"}}}'
            ;;
          4)
            printf '%s\\n' '{"id":3,"result":{"turn":{"id":"turn-feedback-prompt"}}}'
            printf '%s\\n' '{"method":"turn/completed"}'
            exit 0
            ;;
          *)
            exit 0
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server",
        prompt: """
        Title: {{ task.title }}
        {% if task.resume_comment_required %}
        This task was resumed from `Input/Feedback Given`.
        Latest task comment:
        {{ task.latest_comment }}
        {% endif %}
        """,
        max_turns: 1
      )

      Application.put_env(:symphony_elixir, :tracker_adapter_override, SymphonyElixir.Tracker.Memory)

      Application.put_env(:symphony_elixir, :memory_tracker_comments, %{
        "issue-feedback-prompt" => [
          %{"content" => "Old note"},
          %{"content" => "Please address the review feedback in src/foo.ts before continuing."}
        ]
      })

      issue = %Issue{
        id: "issue-feedback-prompt",
        identifier: "LT-FEEDBACK",
        title: "Resume from feedback",
        description: "Continue the implementation after review feedback",
        state: "Input/Feedback Given"
      }

      assert :ok =
               AgentRunner.run(issue, nil,
                 issue_state_fetcher: fn _issue_ids -> {:ok, []} end,
                 max_turns: 1
               )

      prompt_payload = File.read!(input_log)
      assert prompt_payload =~ "This task was resumed from `Input/Feedback Given`."
      assert prompt_payload =~ "Please address the review feedback in src/foo.ts before continuing."
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner stops after a task moves to review even if review is listed as active" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-review-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      turn_log = Path.join(test_root, "turns.log")

      File.mkdir_p!(workspace_root)
      File.write!(turn_log, "")

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      turns=0
      turn_log="#{turn_log}"
      while IFS= read -r _line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-review"}}}'
            ;;
          *)
            turns=$((turns + 1))
            printf '%s\\n' "$turns" >> "$turn_log"
            printf '{"id":3,"result":{"turn":{"id":"turn-%s"}}}\\n' "$turns"
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server",
        tracker_active_states: ["Todo", "In Progress", "Blocked", "In Review"],
        max_turns: 3
      )

      issue = %Issue{
        id: "issue-review-stop",
        identifier: "LT-REVIEWSTOP",
        title: "Stop after review",
        description: "Ensure the agent stops once the task moves to review.",
        state: "In Progress"
      }

      parent = self()

      issue_state_fetcher = fn [issue_id] ->
        send(parent, {:issue_state_refresh, issue_id})

        {:ok,
         [
           %Issue{
             issue
             | state: "In Review"
           }
         ]}
      end

      assert :ok =
               AgentRunner.run(issue, nil,
                 issue_state_fetcher: issue_state_fetcher,
                 max_turns: 3
               )

      assert_receive {:issue_state_refresh, "issue-review-stop"}, 1_000
      refute_receive {:issue_state_refresh, "issue-review-stop"}, 200

      assert turn_log
             |> File.read!()
             |> String.split("\n", trim: true) == ["1"]
    after
      File.rm_rf(test_root)
    end
  end

  test "agent runner stops after a task moves to blocked even if blocked is listed as active" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-agent-runner-blocked-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      codex_binary = Path.join(test_root, "fake-codex")
      turn_log = Path.join(test_root, "turns.log")

      File.mkdir_p!(workspace_root)
      File.write!(turn_log, "")

      File.write!(codex_binary, """
      #!/bin/sh
      count=0
      turns=0
      turn_log="#{turn_log}"
      while IFS= read -r _line; do
        count=$((count + 1))
        case "$count" in
          1)
            printf '%s\\n' '{"id":1,"result":{}}'
            ;;
          2)
            ;;
          3)
            printf '%s\\n' '{"id":2,"result":{"thread":{"id":"thread-blocked"}}}'
            ;;
          *)
            turns=$((turns + 1))
            printf '%s\\n' "$turns" >> "$turn_log"
            printf '{"id":3,"result":{"turn":{"id":"turn-%s"}}}\\n' "$turns"
            printf '%s\\n' '{"method":"turn/completed"}'
            ;;
        esac
      done
      """)

      File.chmod!(codex_binary, 0o755)

      write_workflow_file!(Workflow.workflow_file_path(),
        workspace_root: workspace_root,
        codex_command: "#{codex_binary} app-server",
        tracker_active_states: ["Todo", "In Progress", "Blocked"],
        max_turns: 3
      )

      issue = %Issue{
        id: "issue-blocked-stop",
        identifier: "LT-BLOCKSTOP",
        title: "Stop after blocked",
        description: "Ensure the agent stops once the task moves to blocked.",
        state: "In Progress"
      }

      parent = self()

      issue_state_fetcher = fn [issue_id] ->
        send(parent, {:issue_state_refresh, issue_id})

        {:ok,
         [
           %Issue{
             issue
             | state: "Blocked"
           }
         ]}
      end

      assert :ok =
               AgentRunner.run(issue, nil,
                 issue_state_fetcher: issue_state_fetcher,
                 max_turns: 3
               )

      assert_receive {:issue_state_refresh, "issue-blocked-stop"}, 1_000
      refute_receive {:issue_state_refresh, "issue-blocked-stop"}, 200

      assert turn_log
             |> File.read!()
             |> String.split("\n", trim: true) == ["1"]
    after
      File.rm_rf(test_root)
    end
  end
end
