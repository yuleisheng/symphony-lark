defmodule SymphonyElixir.Codex.DynamicToolTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Codex.DynamicTool

  test "tool_specs advertises the lark_task_api input contract" do
    assert [
             %{
               "description" => description,
               "inputSchema" => %{
                 "properties" => %{
                   "body" => _,
                   "method" => _,
                   "path" => _,
                   "query" => _
                 },
                 "required" => ["method", "path"],
                 "type" => "object"
               },
               "name" => "lark_task_api"
             }
           ] = DynamicTool.tool_specs()

    assert description =~ "Lark Task API"
  end

  test "unsupported tools return a failure payload with the supported tool list" do
    response = DynamicTool.execute("not_a_real_tool", %{})

    assert response["success"] == false

    assert Jason.decode!(response["output"]) == %{
             "error" => %{
               "message" => ~s(Unsupported dynamic tool: "not_a_real_tool".),
               "supportedTools" => ["lark_task_api"]
             }
           }
  end

  test "lark_task_api forwards method, path, query, and body to the request function" do
    test_pid = self()

    response =
      DynamicTool.execute(
        "lark_task_api",
        %{
          "method" => "PATCH",
          "path" => "/open-apis/task/v2/tasks/task-123",
          "query" => %{"user_id_type" => "open_id"},
          "body" => %{"task" => %{"completed_at" => nil}}
        },
        lark_request_fun: fn method, path, opts ->
          send(test_pid, {:lark_request_called, method, path, opts})
          {:ok, %{"code" => 0, "data" => %{"task" => %{"guid" => "task-123"}}}}
        end
      )

    assert_received {:lark_request_called, :patch, "/open-apis/task/v2/tasks/task-123", opts}
    assert Keyword.get(opts, :query) == %{"user_id_type" => "open_id"}
    assert Keyword.get(opts, :body) == %{"task" => %{"completed_at" => nil}}
    assert response["success"] == true
    assert Jason.decode!(response["output"]) == %{"code" => 0, "data" => %{"task" => %{"guid" => "task-123"}}}
  end

  test "lark_task_api validates arguments before calling the client" do
    missing_path =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "GET"},
        lark_request_fun: fn _method, _path, _opts ->
          flunk("request function should not be called when arguments are invalid")
        end
      )

    assert missing_path["success"] == false

    assert Jason.decode!(missing_path["output"]) == %{
             "error" => %{
               "message" => "`lark_task_api.path` must stay under `/open-apis/task/v2/*`.",
               "path" => "nil"
             }
           }

    invalid_body =
      DynamicTool.execute(
        "lark_task_api",
        %{
          "method" => "GET",
          "path" => "/open-apis/task/v2/tasks/task-123",
          "body" => ["not", "a", "map"]
        },
        lark_request_fun: fn _method, _path, _opts ->
          flunk("request function should not be called when body is invalid")
        end
      )

    assert invalid_body["success"] == false

    assert Jason.decode!(invalid_body["output"]) == %{
             "error" => %{
               "message" => "`lark_task_api.body` must be a JSON object when provided."
             }
           }
  end

  test "lark_task_api rejects non-task paths and unsupported methods" do
    bad_path =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "GET", "path" => "/open-apis/wiki/v2/spaces"},
        lark_request_fun: fn _method, _path, _opts ->
          flunk("request function should not be called when path is invalid")
        end
      )

    assert bad_path["success"] == false

    assert Jason.decode!(bad_path["output"]) == %{
             "error" => %{
               "message" => "`lark_task_api.path` must stay under `/open-apis/task/v2/*`.",
               "path" => ~s("/open-apis/wiki/v2/spaces")
             }
           }

    bad_method =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "DELETE", "path" => "/open-apis/task/v2/tasks/task-123"},
        lark_request_fun: fn _method, _path, _opts ->
          flunk("request function should not be called when method is invalid")
        end
      )

    assert bad_method["success"] == false

    assert Jason.decode!(bad_method["output"]) == %{
             "error" => %{
               "message" => "`lark_task_api.method` must be GET, POST, or PATCH.",
               "method" => ~s("DELETE")
             }
           }
  end

  test "lark_task_api accepts task v2 comment paths" do
    test_pid = self()

    response =
      DynamicTool.execute(
        "lark_task_api",
        %{
          "method" => "POST",
          "path" => "/open-apis/task/v2/comments",
          "body" => %{
            "content" => "hello from codex",
            "resource_type" => "task",
            "resource_id" => "task-123"
          }
        },
        lark_request_fun: fn method, path, opts ->
          send(test_pid, {:lark_request_called, method, path, opts})
          {:ok, %{"code" => 0, "data" => %{"comment_id" => "comment-123"}}}
        end
      )

    assert_received {:lark_request_called, :post, "/open-apis/task/v2/comments", opts}

    assert Keyword.get(opts, :body) == %{
             "content" => "hello from codex",
             "resource_type" => "task",
             "resource_id" => "task-123"
           }

    assert response["success"] == true
    assert Jason.decode!(response["output"]) == %{"code" => 0, "data" => %{"comment_id" => "comment-123"}}
  end

  test "lark_task_api formats auth, API, and transport failures" do
    missing_creds =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "GET", "path" => "/open-apis/task/v2/tasks/task-123"},
        lark_request_fun: fn _method, _path, _opts ->
          {:error, :missing_lark_app_credentials}
        end
      )

    assert missing_creds["success"] == false
    assert Jason.decode!(missing_creds["output"])["error"]["message"] =~ "missing Lark auth"

    http_failure =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "GET", "path" => "/open-apis/task/v2/tasks/task-123"},
        lark_request_fun: fn _method, _path, _opts ->
          {:error, {:lark_http_status, 503, %{"code" => 999}}}
        end
      )

    assert http_failure["success"] == false
    assert Jason.decode!(http_failure["output"])["error"]["status"] == 503

    request_failure =
      DynamicTool.execute(
        "lark_task_api",
        %{"method" => "GET", "path" => "/open-apis/task/v2/tasks/task-123"},
        lark_request_fun: fn _method, _path, _opts ->
          {:error, {:lark_request_failed, :timeout}}
        end
      )

    assert request_failure["success"] == false
    assert Jason.decode!(request_failure["output"])["error"]["reason"] == ":timeout"
  end
end
