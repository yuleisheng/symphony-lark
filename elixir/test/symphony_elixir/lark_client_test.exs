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

  test "list_comments uses the task v2 comment endpoint" do
    request_fun = fn spec ->
      send(self(), {:lark_request, spec})
      {:ok, %{status: 200, body: %{"code" => 0, "data" => %{"items" => [%{"comment_id" => "comment-123"}]}}}}
    end

    assert {:ok, [%{"comment_id" => "comment-123"}]} =
             Client.list_comments(
               "task-123",
               tenant_access_token_fun: fn _opts -> {:ok, "tenant-token"} end,
               request_fun: request_fun
             )

    assert_received {:lark_request, spec}
    assert spec.method == :get
    assert spec.url =~ "/open-apis/task/v2/comments"
    assert spec.query["resource_type"] == "task"
    assert spec.query["resource_id"] == "task-123"
    assert spec.query["page_size"] == 50
  end

  test "create_comment uses the task v2 comment endpoint" do
    request_fun = fn spec ->
      send(self(), {:lark_request, spec})
      {:ok, %{status: 200, body: %{"code" => 0, "data" => %{"comment_id" => "comment-123"}}}}
    end

    assert {:ok, %{"code" => 0, "data" => %{"comment_id" => "comment-123"}}} =
             Client.create_comment(
               "task-123",
               "hello from codex",
               tenant_access_token_fun: fn _opts -> {:ok, "tenant-token"} end,
               request_fun: request_fun
             )

    assert_received {:lark_request, spec}
    assert spec.method == :post
    assert spec.url =~ "/open-apis/task/v2/comments"

    assert spec.body == %{
             "content" => "hello from codex",
             "resource_type" => "task",
             "resource_id" => "task-123"
           }
  end
end
