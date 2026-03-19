defmodule SymphonyElixir.Lark.Client do
  @moduledoc """
  Thin Lark OpenAPI client for task operations, including Task v2 comments.
  """

  alias SymphonyElixir.{Config, Lark.Auth}

  @default_page_size 50
  @custom_field_page_size 100
  @task_api_prefix "/open-apis/task/v2/"

  @type request_spec :: %{
          method: atom(),
          url: String.t(),
          headers: [{String.t(), String.t()}],
          query: map(),
          body: map() | nil
        }

  @spec request(atom() | String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(method, path, opts \\ []) do
    tenant_access_token_fun = Keyword.get(opts, :tenant_access_token_fun, &Auth.tenant_access_token/1)
    request_fun = Keyword.get(opts, :request_fun, &perform_request/1)

    with {:ok, normalized_method} <- normalize_method(method),
         {:ok, normalized_path} <- normalize_path(path),
         {:ok, tenant_access_token} <- tenant_access_token_fun.([]),
         {:ok, response} <-
           request_fun.(build_request_spec(normalized_method, normalized_path, tenant_access_token, opts)) do
      normalize_response(response)
    end
  end

  @spec get_task(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_task(task_guid, opts \\ []) when is_binary(task_guid) do
    with {:ok, body} <- request(:get, task_path(task_guid), opts) do
      {:ok, Map.get(body["data"] || %{}, "task", body["data"] || %{})}
    end
  end

  @spec patch_task(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def patch_task(task_guid, attrs, opts \\ []) when is_binary(task_guid) and is_map(attrs) do
    request(
      :patch,
      task_path(task_guid),
      Keyword.put(opts, :body, %{
        "task" => attrs,
        "update_fields" => attrs |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
      })
    )
  end

  @spec list_tasklist_tasks(String.t(), boolean(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_tasklist_tasks(tasklist_guid, completed?, opts \\ [])
      when is_binary(tasklist_guid) and is_boolean(completed?) do
    paginate_collection(
      tasklist_tasks_path(tasklist_guid),
      %{
        "completed" => completed?,
        "page_size" => Keyword.get(opts, :page_size, @default_page_size)
      },
      opts
    )
  end

  @spec list_custom_fields(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_custom_fields(resource_id, opts \\ []) when is_binary(resource_id) do
    paginate_collection(
      "#{@task_api_prefix}custom_fields",
      %{
        "resource_type" => "tasklist",
        "resource_id" => resource_id,
        "page_size" => Keyword.get(opts, :page_size, @custom_field_page_size)
      },
      opts
    )
  end

  @spec list_comments(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_comments(task_guid, opts \\ []) when is_binary(task_guid) do
    paginate_collection(
      task_comments_path(),
      %{
        "resource_type" => "task",
        "resource_id" => task_guid,
        "page_size" => Keyword.get(opts, :page_size, @default_page_size)
      },
      opts
    )
  end

  @spec create_comment(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def create_comment(task_guid, content, opts \\ [])
      when is_binary(task_guid) and is_binary(content) do
    request(
      :post,
      task_comments_path(),
      Keyword.put(opts, :body, %{
        "content" => content,
        "resource_type" => "task",
        "resource_id" => task_guid
      })
    )
  end

  @spec task_api_prefix() :: String.t()
  def task_api_prefix, do: @task_api_prefix

  defp paginate_collection(path, base_query, opts) do
    do_paginate_collection(path, base_query, opts, [])
  end

  defp do_paginate_collection(path, base_query, opts, acc) do
    with {:ok, body} <- request(:get, path, Keyword.put(opts, :query, base_query)),
         data when is_map(data) <- body["data"] || %{},
         items when is_list(items) <- extract_collection_items(data) do
      updated_acc = acc ++ items

      case extract_next_page_token(data) do
        nil ->
          {:ok, updated_acc}

        next_page_token ->
          do_paginate_collection(
            path,
            Map.put(base_query, "page_token", next_page_token),
            opts,
            updated_acc
          )
      end
    else
      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, {:unexpected_lark_collection_response, path}}
    end
  end

  defp build_request_spec(method, path, tenant_access_token, opts) do
    tracker = Config.settings!().tracker

    %{
      method: method,
      url: normalize_endpoint(tracker.endpoint) <> path,
      headers: [
        {"authorization", "Bearer " <> tenant_access_token},
        {"content-type", "application/json"}
      ],
      query: normalize_query(Keyword.get(opts, :query, %{})),
      body: Keyword.get(opts, :body)
    }
  end

  defp perform_request(%{method: method, url: url, headers: headers, query: query, body: body}) do
    req =
      Req.new(
        method: method,
        url: url,
        headers: headers,
        params: query
      )

    req =
      case body do
        %{} = json_body -> Req.merge(req, json: json_body)
        _ -> req
      end

    case Req.request(req) do
      {:ok, %{status: status, body: response_body}} ->
        {:ok, %{status: status, body: response_body}}

      {:error, reason} ->
        {:error, {:lark_request_failed, reason}}
    end
  end

  defp normalize_response(%{status: status, body: body}) when status in 200..299 and is_map(body) do
    case body do
      %{"code" => 0} ->
        {:ok, body}

      %{"code" => code, "msg" => message} ->
        {:error, {:lark_api_error, code, message, body}}

      _ ->
        {:error, {:unexpected_lark_response, body}}
    end
  end

  defp normalize_response(%{status: status, body: body}) do
    {:error, {:lark_http_status, status, body}}
  end

  defp normalize_method(method) when method in [:get, :post, :patch], do: {:ok, method}

  defp normalize_method(method) when is_binary(method) do
    case String.downcase(String.trim(method)) do
      "get" -> {:ok, :get}
      "post" -> {:ok, :post}
      "patch" -> {:ok, :patch}
      other -> {:error, {:unsupported_lark_method, other}}
    end
  end

  defp normalize_method(method), do: {:error, {:unsupported_lark_method, method}}

  defp normalize_path(path) when is_binary(path) do
    trimmed = String.trim(path)

    cond do
      trimmed == "" ->
        {:error, :missing_lark_path}

      task_api_path?(trimmed) ->
        {:ok, trimmed}

      true ->
        {:error, {:unsupported_lark_path, trimmed}}
    end
  end

  defp normalize_path(path), do: {:error, {:unsupported_lark_path, path}}

  defp normalize_query(query) when is_map(query), do: query
  defp normalize_query(_query), do: %{}

  defp task_api_path?(path) do
    String.starts_with?(path, @task_api_prefix)
  end

  defp task_path(task_guid) do
    "#{@task_api_prefix}tasks/#{URI.encode(task_guid)}"
  end

  defp task_comments_path, do: "#{@task_api_prefix}comments"

  defp tasklist_tasks_path(tasklist_guid) do
    "#{@task_api_prefix}tasklists/#{URI.encode(tasklist_guid)}/tasks"
  end

  defp extract_collection_items(data) when is_map(data) do
    cond do
      is_list(data["items"]) -> data["items"]
      is_list(data["tasks"]) -> data["tasks"]
      is_list(data["comments"]) -> data["comments"]
      is_list(data["custom_fields"]) -> data["custom_fields"]
      true -> []
    end
  end

  defp extract_next_page_token(data) when is_map(data) do
    cond do
      data["has_more"] == true and is_binary(data["page_token"]) and data["page_token"] != "" ->
        data["page_token"]

      data["has_more"] == true and is_binary(data["next_page_token"]) and data["next_page_token"] != "" ->
        data["next_page_token"]

      true ->
        nil
    end
  end

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    endpoint
    |> String.trim()
    |> String.trim_trailing("/")
  end
end
