defmodule SymphonyElixir.LarkConfigTest do
  use SymphonyElixir.TestSupport

  test "config validates required Lark tracker fields" do
    previous_app_id = System.get_env("LARK_APP_ID")
    previous_app_secret = System.get_env("LARK_APP_SECRET")
    previous_tasklist_guid = System.get_env("LARK_TASKLIST_GUID")

    on_exit(fn ->
      restore_env("LARK_APP_ID", previous_app_id)
      restore_env("LARK_APP_SECRET", previous_app_secret)
      restore_env("LARK_TASKLIST_GUID", previous_tasklist_guid)
    end)

    System.delete_env("LARK_APP_ID")
    System.delete_env("LARK_APP_SECRET")
    System.delete_env("LARK_TASKLIST_GUID")

    write_workflow_file!(Workflow.workflow_file_path(), tracker_app_id: nil)
    assert {:error, :missing_lark_app_id} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(), tracker_app_id: "app-id", tracker_app_secret: nil)
    assert {:error, :missing_lark_app_secret} = Config.validate!()

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_app_secret: "app-secret",
      tracker_tasklist_guid: nil
    )

    assert {:error, :missing_lark_tasklist_guid} = Config.validate!()
  end

  test "config validates required workspace root env when workflow references it" do
    previous_workspace_root = System.get_env("SYMPHONY_WORKSPACE_ROOT")

    on_exit(fn ->
      restore_env("SYMPHONY_WORKSPACE_ROOT", previous_workspace_root)
    end)

    System.delete_env("SYMPHONY_WORKSPACE_ROOT")
    write_workflow_file!(Workflow.workflow_file_path(), workspace_root: "$SYMPHONY_WORKSPACE_ROOT")
    assert {:error, :missing_symphony_workspace_root} = Config.validate!()

    System.put_env("SYMPHONY_WORKSPACE_ROOT", "")
    assert {:error, :missing_symphony_workspace_root} = Config.validate!()
  end

  test "config validates required repo root env when the default repo hook references it" do
    previous_repo_root = System.get_env("SYMPHONY_REPO_ROOT")

    on_exit(fn ->
      restore_env("SYMPHONY_REPO_ROOT", previous_repo_root)
    end)

    System.delete_env("SYMPHONY_REPO_ROOT")

    write_workflow_file!(Workflow.workflow_file_path(),
      workspace_root: Path.join(System.tmp_dir!(), "symphony_workspaces"),
      hook_after_create:
        "test -n \"$SYMPHONY_REPO_ROOT\" || { echo \"SYMPHONY_REPO_ROOT is required\"; exit 1; }; source_origin=\"$(git -C \"$SYMPHONY_REPO_ROOT\" remote get-url origin 2>/dev/null || true)\"; git clone --local \"$SYMPHONY_REPO_ROOT\" . && if [ -n \"$source_origin\" ]; then git remote set-url origin \"$source_origin\"; fi"
    )

    assert {:error, :missing_symphony_repo_root} = Config.validate!()

    System.put_env("SYMPHONY_REPO_ROOT", "")
    assert {:error, :missing_symphony_repo_root} = Config.validate!()
  end

  test "config validates that the local codex command is available on PATH" do
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
    end)

    System.put_env("PATH", "/bin")
    write_workflow_file!(Workflow.workflow_file_path(), codex_command: "codex app-server")

    assert {:error, {:codex_command_not_found, "codex", "codex app-server"}} = Config.validate!()
  end

  test "config does not require a local codex binary when only remote worker hosts are configured" do
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      restore_env("PATH", previous_path)
    end)

    System.put_env("PATH", "/bin")

    write_workflow_file!(Workflow.workflow_file_path(),
      codex_command: "codex app-server",
      worker_ssh_hosts: ["builder@example.com"]
    )

    assert :ok = Config.validate!()
  end

  test "Lark secrets resolve from environment variables" do
    previous_app_id = System.get_env("LARK_APP_ID")
    previous_app_secret = System.get_env("LARK_APP_SECRET")
    previous_tasklist_guid = System.get_env("LARK_TASKLIST_GUID")

    on_exit(fn ->
      restore_env("LARK_APP_ID", previous_app_id)
      restore_env("LARK_APP_SECRET", previous_app_secret)
      restore_env("LARK_TASKLIST_GUID", previous_tasklist_guid)
    end)

    System.put_env("LARK_APP_ID", "env-app-id")
    System.put_env("LARK_APP_SECRET", "env-app-secret")
    System.put_env("LARK_TASKLIST_GUID", "env-tasklist-guid")

    write_workflow_file!(Workflow.workflow_file_path(),
      tracker_app_id: nil,
      tracker_app_secret: nil,
      tracker_tasklist_guid: nil
    )

    config = Config.settings!()
    assert config.tracker.app_id == "env-app-id"
    assert config.tracker.app_secret == "env-app-secret"
    assert config.tracker.tasklist_guid == "env-tasklist-guid"
  end

  test "workflow file path defaults to WORKFLOW.lark.md in the current working directory" do
    original_workflow_path = Workflow.workflow_file_path()
    on_exit(fn -> Workflow.set_workflow_file_path(original_workflow_path) end)

    Workflow.clear_workflow_file_path()

    assert Workflow.workflow_file_path() == Path.join(File.cwd!(), "WORKFLOW.lark.md")
  end

  test "default prompt template is task-oriented" do
    write_workflow_file!(Workflow.workflow_file_path(), prompt: "")

    prompt =
      PromptBuilder.build_prompt(%Issue{
        id: "task-123",
        identifier: "LT-12345678",
        title: "Use the Lark prompt template",
        description: "Ensure the default prompt renders task fields correctly",
        state: "Todo"
      })

    assert prompt =~ "You are working on a Lark task."
    assert prompt =~ "LT-12345678"
    assert prompt =~ "Task GUID: task-123"
    assert prompt =~ "/open-apis/task/v2/"
    assert prompt =~ "task.custom_fields"
    assert prompt =~ "Use the Lark prompt template"
  end
end
