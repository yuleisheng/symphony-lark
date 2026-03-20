defmodule SymphonyElixirWeb.PresenterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.PathSafety
  alias SymphonyElixirWeb.Presenter

  test "issue payload falls back to the resolved assigned workspace path" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-presenter-#{System.unique_integer([:positive])}"
      )

    orchestrator_name = Module.concat(__MODULE__, :PresenterOrchestrator)

    try do
      workspace_root = Path.join(test_root, "workspaces")
      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      issue = %Issue{
        id: "issue-presenter",
        identifier: "LT 77/fallback",
        title: "Presenter fallback",
        description: "Use the resolved workspace path",
        state: "In Progress"
      }

      expected_workspace =
        Path.join(workspace_root, "LT_77_fallback")
        |> PathSafety.canonicalize()
        |> elem(1)

      {:ok, pid} = Orchestrator.start_link(name: orchestrator_name)

      on_exit(fn ->
        if Process.alive?(pid) do
          Process.exit(pid, :normal)
        end
      end)

      initial_state = :sys.get_state(pid)

      :sys.replace_state(pid, fn _state ->
        %{
          initial_state
          | running: %{
              issue.id => %{
                pid: self(),
                ref: make_ref(),
                identifier: issue.identifier,
                issue: issue,
                worker_host: nil,
                workspace_path: nil,
                session_id: nil,
                last_codex_message: nil,
                last_codex_timestamp: nil,
                last_codex_event: nil,
                codex_app_server_pid: nil,
                codex_input_tokens: 0,
                codex_output_tokens: 0,
                codex_total_tokens: 0,
                turn_count: 0,
                started_at: DateTime.utc_now()
              }
            },
            claimed: MapSet.put(initial_state.claimed, issue.id)
        }
      end)

      assert {:ok, payload} = Presenter.issue_payload(issue.identifier, orchestrator_name, 1_000)
      assert payload.workspace.path == expected_workspace
    after
      File.rm_rf(test_root)
    end
  end
end
