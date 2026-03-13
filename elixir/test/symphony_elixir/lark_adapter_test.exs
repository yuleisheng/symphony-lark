defmodule SymphonyElixir.LarkAdapterTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Lark.Adapter

  defmodule FakeLarkClient do
    def list_custom_fields(_tasklist_guid) do
      {:ok,
       [
         %{
           "guid" => "field-status",
           "name" => "Status",
           "type" => "single_select",
           "single_select_setting" => %{
             "options" => [
               %{"guid" => "opt-todo", "name" => "Todo"},
               %{"guid" => "opt-progress", "name" => "In Progress"},
               %{"guid" => "opt-done", "name" => "Done"}
             ]
           }
         }
       ]}
    end

    def list_tasklist_tasks(_tasklist_guid, completed?) do
      entries =
        case completed? do
          false -> [%{"guid" => "task-open"}, %{"guid" => "task-done"}]
          true -> [%{"guid" => "task-done"}]
        end

      {:ok, entries}
    end

    def get_task("task-open") do
      {:ok,
       %{
         "guid" => "task-open",
         "summary" => "Open task",
         "description" => "Needs work",
         "created_at" => "2026-03-13T00:00:00Z",
         "custom_fields" => [%{"guid" => "field-status", "single_select_value" => "opt-progress"}]
       }}
    end

    def get_task("task-done") do
      {:ok,
       %{
         "guid" => "task-done",
         "summary" => "Done task",
         "description" => "Already finished",
         "created_at" => "2026-03-12T00:00:00Z",
         "completed_at" => "2026-03-12T03:00:00Z",
         "custom_fields" => [%{"guid" => "field-status", "single_select_value" => "opt-done"}]
       }}
    end

    def create_comment(task_guid, body) do
      send(self(), {:fake_lark_comment, task_guid, body})
      {:ok, %{"code" => 0}}
    end

    def patch_task(task_guid, attrs) do
      send(self(), {:fake_lark_patch, task_guid, attrs})
      {:ok, %{"code" => 0}}
    end
  end

  defmodule SummaryStateLarkClient do
    def list_custom_fields(_tasklist_guid) do
      FakeLarkClient.list_custom_fields("unused")
    end

    def list_tasklist_tasks(_tasklist_guid, completed?) do
      entries =
        case completed? do
          false ->
            [
              %{
                "guid" => "task-todo",
                "summary" => "Todo task",
                "description" => "Ready to pick up",
                "created_at" => "2026-03-14T00:00:00Z",
                "custom_fields" => [%{"guid" => "field-status", "single_select_value" => "opt-todo"}]
              }
            ]

          true ->
            []
        end

      {:ok, entries}
    end

    def get_task("task-todo") do
      {:ok,
       %{
         "guid" => "task-todo",
         "summary" => "Todo task",
         "description" => "Ready to pick up"
       }}
    end
  end

  setup do
    Application.put_env(:symphony_elixir, :lark_client_module, FakeLarkClient)
    Adapter.clear_cache_for_test()
    :ok
  end

  test "fetch_candidate_issues filters to active task states" do
    assert {:ok, tasks} = Adapter.fetch_candidate_issues()

    assert Enum.map(tasks, & &1.id) == ["task-open"]
    assert Enum.map(tasks, & &1.state) == ["In Progress"]
    assert Enum.map(tasks, & &1.identifier) == ["LT-TASK-OPE"]
  end

  test "fetch_issues_by_states returns open and completed matches" do
    assert {:ok, tasks} = Adapter.fetch_issues_by_states(["Done"])
    assert Enum.map(tasks, & &1.id) == ["task-done"]
    assert Enum.at(tasks, 0).completed_at != nil
  end

  test "tasklist summaries drive state hydration when task details omit custom fields" do
    Application.put_env(:symphony_elixir, :lark_client_module, SummaryStateLarkClient)
    Adapter.clear_cache_for_test()

    assert {:ok, [%{id: "task-todo", state: "Todo"} = task]} = Adapter.fetch_candidate_issues()
    assert task.title == "Todo task"

    assert {:ok, [%{id: "task-todo", state: "Todo"}]} =
             Adapter.fetch_issue_states_by_ids(["task-todo"])
  end

  test "update_issue_state patches the Status field and terminal completion" do
    assert :ok = Adapter.update_issue_state("task-open", "Done")

    assert_received {:fake_lark_patch, "task-open", attrs}
    assert get_in(attrs, ["custom_fields", Access.at(0), "guid"]) == "field-status"
    assert get_in(attrs, ["custom_fields", Access.at(0), "single_select_value"]) == "opt-done"
    assert is_binary(attrs["completed_at"])
  end

  test "create_comment delegates to the Lark client" do
    assert :ok = Adapter.create_comment("task-open", "hello from codex")
    assert_received {:fake_lark_comment, "task-open", "hello from codex"}
  end
end
