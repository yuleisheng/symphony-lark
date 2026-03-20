defmodule SymphonyElixir.WorkspaceTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.PathSafety

  test "assign_for_issue resolves the canonical sanitized path and prepare_assigned_workspace materializes it" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-workspace-#{System.unique_integer([:positive])}"
      )

    try do
      workspace_root = Path.join(test_root, "workspaces")
      File.mkdir_p!(workspace_root)

      write_workflow_file!(Workflow.workflow_file_path(), workspace_root: workspace_root)

      issue = %Issue{
        id: "issue-workspace",
        identifier: "LT 42/rework",
        title: "Prepare assigned workspace",
        state: "Todo"
      }

      expected_workspace =
        Path.join(workspace_root, "LT_42_rework")
        |> PathSafety.canonicalize()
        |> elem(1)

      assert {:ok, ^expected_workspace} = Workspace.assign_for_issue(issue)
      assert {:ok, ^expected_workspace} = Workspace.prepare_assigned_workspace(expected_workspace, issue)
      assert File.dir?(expected_workspace)
    after
      File.rm_rf(test_root)
    end
  end
end
