defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes client-side tool calls requested by Codex app-server turns.
  """

  alias SymphonyElixir.Lark.Client

  @lark_task_api_tool "lark_task_api"
  @lark_task_api_prefix "/open-apis/task/v2/"
  @lark_task_api_description """
  Execute an authenticated Lark Task v2 API request using Symphony's configured tenant credentials.
  """
  @lark_task_api_input_schema %{
    "type" => "object",
    "additionalProperties" => false,
    "required" => ["method", "path"],
    "properties" => %{
      "method" => %{
        "type" => "string",
        "enum" => ["GET", "POST", "PATCH"],
        "description" => "HTTP method for the Lark Task v2 API request."
      },
      "path" => %{
        "type" => "string",
        "description" => "API path under /open-apis/task/v2/."
      },
      "query" => %{
        "type" => ["object", "null"],
        "description" => "Optional query string parameters.",
        "additionalProperties" => true
      },
      "body" => %{
        "type" => ["object", "null"],
        "description" => "Optional JSON request body.",
        "additionalProperties" => true
      }
    }
  }

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @lark_task_api_tool ->
        execute_lark_task_api(arguments, opts)

      other ->
        failure_response(%{
          "error" => %{
            "message" => "Unsupported dynamic tool: #{inspect(other)}.",
            "supportedTools" => supported_tool_names()
          }
        })
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        "name" => @lark_task_api_tool,
        "description" => @lark_task_api_description,
        "inputSchema" => @lark_task_api_input_schema
      }
    ]
  end

  defp execute_lark_task_api(arguments, opts) do
    request_fun = Keyword.get(opts, :lark_request_fun, &Client.request/3)

    with {:ok, method, path, request_opts} <- normalize_lark_task_api_arguments(arguments),
         {:ok, response} <- request_fun.(method, path, request_opts) do
      success_response(response)
    else
      {:error, reason} ->
        failure_response(tool_error_payload(reason))
    end
  end

  defp normalize_lark_task_api_arguments(arguments) when is_map(arguments) do
    with {:ok, method} <- normalize_method(Map.get(arguments, "method") || Map.get(arguments, :method)),
         {:ok, path} <- normalize_path(Map.get(arguments, "path") || Map.get(arguments, :path)),
         {:ok, query} <- normalize_optional_map(Map.get(arguments, "query") || Map.get(arguments, :query), :query),
         {:ok, body} <- normalize_optional_map(Map.get(arguments, "body") || Map.get(arguments, :body), :body) do
      {:ok, method, path, [query: query, body: body]}
    end
  end

  defp normalize_lark_task_api_arguments(_arguments), do: {:error, :invalid_arguments}

  defp normalize_method(method) when is_binary(method) do
    case String.upcase(String.trim(method)) do
      "GET" -> {:ok, :get}
      "POST" -> {:ok, :post}
      "PATCH" -> {:ok, :patch}
      other -> {:error, {:unsupported_lark_method, other}}
    end
  end

  defp normalize_method(method), do: {:error, {:unsupported_lark_method, method}}

  defp normalize_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" ->
        {:error, :missing_lark_path}

      String.starts_with?(trimmed, @lark_task_api_prefix) ->
        {:ok, trimmed}

      true ->
        {:error, {:unsupported_lark_path, trimmed}}
    end
  end

  defp normalize_path(path), do: {:error, {:unsupported_lark_path, path}}

  defp normalize_optional_map(nil, _field), do: {:ok, nil}
  defp normalize_optional_map(%{} = map, _field), do: {:ok, map}
  defp normalize_optional_map(_value, field), do: {:error, {:invalid_lark_payload, field}}

  defp success_response(payload) do
    dynamic_tool_response(true, encode_payload(payload))
  end

  defp failure_response(payload) do
    dynamic_tool_response(false, encode_payload(payload))
  end

  defp dynamic_tool_response(success, output) when is_boolean(success) and is_binary(output) do
    %{
      "success" => success,
      "output" => output,
      "contentItems" => [
        %{
          "type" => "inputText",
          "text" => output
        }
      ]
    }
  end

  defp encode_payload(payload) when is_map(payload) or is_list(payload) do
    Jason.encode!(payload, pretty: true)
  end

  defp encode_payload(payload), do: inspect(payload)

  defp tool_error_payload(:invalid_arguments) do
    %{
      "error" => %{
        "message" => "`lark_task_api` expects an object with `method`, `path`, and optional `query` and `body` maps."
      }
    }
  end

  defp tool_error_payload(:missing_lark_path) do
    %{
      "error" => %{
        "message" => "`lark_task_api.path` must be a non-empty Task v2 API path."
      }
    }
  end

  defp tool_error_payload({:unsupported_lark_method, method}) do
    %{
      "error" => %{
        "message" => "`lark_task_api.method` must be GET, POST, or PATCH.",
        "method" => inspect(method)
      }
    }
  end

  defp tool_error_payload({:unsupported_lark_path, path}) do
    %{
      "error" => %{
        "message" => "`lark_task_api.path` must stay under `/open-apis/task/v2/*`.",
        "path" => inspect(path)
      }
    }
  end

  defp tool_error_payload({:invalid_lark_payload, field}) do
    %{
      "error" => %{
        "message" => "`lark_task_api.#{field}` must be a JSON object when provided."
      }
    }
  end

  defp tool_error_payload(:missing_lark_app_credentials) do
    %{
      "error" => %{
        "message" => "Symphony is missing Lark auth. Set `tracker.app_id` and `tracker.app_secret` or export `LARK_APP_ID` and `LARK_APP_SECRET`."
      }
    }
  end

  defp tool_error_payload({:lark_auth_http_status, status, body}) do
    %{
      "error" => %{
        "message" => "Lark auth failed with HTTP #{status}.",
        "status" => status,
        "body" => body
      }
    }
  end

  defp tool_error_payload({:lark_auth_error, code, message, body}) do
    %{
      "error" => %{
        "message" => "Lark auth failed.",
        "code" => code,
        "detail" => message,
        "body" => body
      }
    }
  end

  defp tool_error_payload({:lark_http_status, status, body}) do
    %{
      "error" => %{
        "message" => "Lark Task API request failed with HTTP #{status}.",
        "status" => status,
        "body" => body
      }
    }
  end

  defp tool_error_payload({:lark_api_error, code, message, body}) do
    %{
      "error" => %{
        "message" => "Lark Task API request failed.",
        "code" => code,
        "detail" => message,
        "body" => body
      }
    }
  end

  defp tool_error_payload({:lark_request_failed, reason}) do
    %{
      "error" => %{
        "message" => "Lark Task API request failed before receiving a successful response.",
        "reason" => inspect(reason)
      }
    }
  end

  defp tool_error_payload(reason) do
    %{
      "error" => %{
        "message" => "Lark Task API tool execution failed.",
        "reason" => inspect(reason)
      }
    }
  end

  defp supported_tool_names do
    Enum.map(tool_specs(), & &1["name"])
  end
end
