defmodule SymphonyElixir.LarkClientTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Lark.Client

  test "patch_task includes update_fields for changed task attributes" do
    request_fun = fn spec ->
      send(self(), {:lark_request, spec})
      {:ok, %{status: 200, body: %{"code" => 0, "data" => %{"task" => %{"guid" => "task-123"}}}}}
    end

    assert {:ok, %{"data" => %{"task" => %{"guid" => "task-123"}}}} =
             Client.patch_task(
               "task-123",
               %{
                 "custom_fields" => [%{"guid" => "field-status", "single_select_value" => "opt-progress"}],
                 "completed_at" => nil
               },
               tenant_access_token_fun: fn _opts -> {:ok, "tenant-token"} end,
               request_fun: request_fun
             )

    assert_received {:lark_request, spec}
    assert spec.method == :patch
    assert spec.url =~ "/open-apis/task/v2/tasks/task-123"
    assert spec.body["task"]["custom_fields"] != nil
    assert MapSet.new(spec.body["update_fields"]) == MapSet.new(["completed_at", "custom_fields"])
  end
end
