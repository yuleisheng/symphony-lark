defmodule SymphonyElixir.Lark.Adapter do
  @moduledoc """
  Lark-backed tracker adapter.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.{Config, Lark.Client, Tracker.Task}

  @state_field_cache_prefix {__MODULE__, :state_field}

  @type state_field :: %{
          field_guid: String.t(),
          field_name: String.t(),
          option_guid_by_state: %{optional(String.t()) => String.t()},
          option_state_by_guid: %{optional(String.t()) => String.t()}
        }

  @spec fetch_candidate_issues() :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_candidate_issues do
    with {:ok, state_field} <- resolve_state_field(),
         {:ok, tasks} <- fetch_tasks_for_completion_state(false, state_field) do
      {:ok, Enum.filter(tasks, &active_task_state?(&1.state))}
    end
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) when is_list(state_names) do
    normalized_states =
      state_names
      |> Enum.map(&normalize_state/1)
      |> MapSet.new()

    if MapSet.size(normalized_states) == 0 do
      {:ok, []}
    else
      with {:ok, state_field} <- resolve_state_field(),
           {:ok, open_tasks} <- fetch_tasks_for_completion_state(false, state_field),
           {:ok, completed_tasks} <- fetch_tasks_for_completion_state(true, state_field) do
        {:ok,
         (open_tasks ++ completed_tasks)
         |> dedupe_tasks()
         |> Enum.filter(fn %Task{state: state} ->
           MapSet.member?(normalized_states, normalize_state(state))
         end)}
      end
    end
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) when is_list(issue_ids) do
    ids =
      issue_ids
      |> Enum.filter(&is_binary/1)
      |> Enum.uniq()

    if ids == [] do
      {:ok, []}
    else
      with {:ok, state_field} <- resolve_state_field() do
        hydrate_tasks(Enum.map(ids, &%{"guid" => &1}), state_field)
      end
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(task_guid, body) when is_binary(task_guid) and is_binary(body) do
    case client_module().create_comment(task_guid, body) do
      {:ok, _response} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(task_guid, state_name)
      when is_binary(task_guid) and is_binary(state_name) do
    with {:ok, state_field} <- resolve_state_field(),
         {:ok, option_guid} <- option_guid_for_state(state_field, state_name),
         attrs <- build_state_update_attrs(state_field, option_guid, state_name),
         {:ok, _response} <- client_module().patch_task(task_guid, attrs) do
      :ok
    end
  end

  @doc false
  @spec resolve_state_field_for_test() :: {:ok, state_field()} | {:error, term()}
  def resolve_state_field_for_test do
    resolve_state_field()
  end

  @doc false
  @spec normalize_task_for_test(map(), state_field()) :: Task.t()
  def normalize_task_for_test(task, state_field) when is_map(task) and is_map(state_field) do
    normalize_task(task, state_field)
  end

  @doc false
  @spec clear_cache_for_test() :: :ok
  def clear_cache_for_test do
    :persistent_term.erase(state_field_cache_key())
    :ok
  end

  defp fetch_tasks_for_completion_state(completed?, state_field) do
    tracker = Config.settings!().tracker

    with {:ok, task_entries} <- client_module().list_tasklist_tasks(tracker.tasklist_guid, completed?) do
      hydrate_tasks(task_entries, state_field)
    end
  end

  defp hydrate_tasks(task_entries, state_field) when is_list(task_entries) do
    task_entries
    |> Enum.map(&task_guid/1)
    |> Enum.filter(&is_binary/1)
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn task_guid, {:ok, acc} ->
      case client_module().get_task(task_guid) do
        {:ok, task} when is_map(task) ->
          {:cont, {:ok, [normalize_task(task, state_field) | acc]}}

        {:ok, other} ->
          {:halt, {:error, {:unexpected_lark_task_response, task_guid, other}}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tasks} -> {:ok, Enum.reverse(tasks)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp dedupe_tasks(tasks) do
    tasks
    |> Enum.reduce({MapSet.new(), []}, fn %Task{id: id} = task, {seen, acc} ->
      if MapSet.member?(seen, id) do
        {seen, acc}
      else
        {MapSet.put(seen, id), [task | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp resolve_state_field do
    cache_key = state_field_cache_key()

    case :persistent_term.get(cache_key, nil) do
      %{field_guid: _, option_guid_by_state: _, option_state_by_guid: _} = state_field ->
        {:ok, state_field}

      _ ->
        fetch_and_cache_state_field(cache_key)
    end
  end

  defp fetch_and_cache_state_field(cache_key) do
    tracker = Config.settings!().tracker

    with {:ok, custom_fields} <- client_module().list_custom_fields(tracker.tasklist_guid),
         {:ok, state_field} <- find_state_field(custom_fields, tracker.state_field_name) do
      :persistent_term.put(cache_key, state_field)
      {:ok, state_field}
    end
  end

  defp find_state_field(custom_fields, field_name) when is_list(custom_fields) and is_binary(field_name) do
    normalized_name = normalize_state(field_name)

    custom_fields
    |> Enum.find(fn custom_field ->
      normalize_state(custom_field["name"] || custom_field[:name]) == normalized_name
    end)
    |> case do
      nil ->
        {:error, {:missing_lark_state_field, field_name}}

      custom_field ->
        normalize_state_field(custom_field, field_name)
    end
  end

  defp normalize_state_field(custom_field, fallback_field_name) do
    field_type = normalize_field_type(custom_field["type"] || custom_field[:type])
    field_guid = custom_field["guid"] || custom_field[:guid]

    cond do
      field_type != :single_select ->
        {:error, {:invalid_lark_state_field_type, field_type}}

      not is_binary(field_guid) or field_guid == "" ->
        {:error, {:invalid_lark_state_field_guid, custom_field}}

      true ->
        options =
          custom_field["single_select_setting"] ||
            custom_field[:single_select_setting] ||
            custom_field["select_setting"] ||
            custom_field[:select_setting] ||
            %{}

        option_entries = Map.get(options, "options") || Map.get(options, :options) || []

        {option_guid_by_state, option_state_by_guid} =
          Enum.reduce(option_entries, {%{}, %{}}, fn option, {guid_by_state, state_by_guid} ->
            option_name = option["name"] || option[:name]
            option_guid = option["guid"] || option[:guid]

            if is_binary(option_name) and option_name != "" and is_binary(option_guid) and option_guid != "" do
              normalized_state = normalize_state(option_name)

              {
                Map.put(guid_by_state, normalized_state, option_guid),
                Map.put(state_by_guid, option_guid, option_name)
              }
            else
              {guid_by_state, state_by_guid}
            end
          end)

        {:ok,
         %{
           field_guid: field_guid,
           field_name: custom_field["name"] || custom_field[:name] || fallback_field_name,
           option_guid_by_state: option_guid_by_state,
           option_state_by_guid: option_state_by_guid
         }}
    end
  end

  defp normalize_task(task, state_field) do
    task_guid = task_guid(task)

    %Task{
      id: task_guid,
      identifier: synthetic_identifier(task_guid),
      title: string_value(task, ["summary", "title", "name"]),
      description: string_value(task, ["description", "notes", "content"]),
      priority: nil,
      state: state_name_for_task(task, state_field),
      branch_name: nil,
      url: nil,
      assignee_id: nil,
      blocked_by: [],
      labels: [],
      assigned_to_worker: true,
      created_at: parse_datetime(task["created_at"] || task[:created_at]),
      updated_at: parse_datetime(task["updated_at"] || task[:updated_at]),
      completed_at: parse_datetime(task["completed_at"] || task[:completed_at])
    }
  end

  defp state_name_for_task(task, %{field_guid: field_guid, option_state_by_guid: option_state_by_guid}) do
    custom_fields = task["custom_fields"] || task[:custom_fields] || []

    custom_fields
    |> Enum.find(fn custom_field ->
      (custom_field["guid"] || custom_field[:guid]) == field_guid
    end)
    |> case do
      nil ->
        nil

      custom_field ->
        cond do
          is_binary(custom_field["display_value"]) and custom_field["display_value"] != "" ->
            custom_field["display_value"]

          is_binary(custom_field[:display_value]) and custom_field[:display_value] != "" ->
            custom_field[:display_value]

          is_binary(custom_field["single_select_value"]) ->
            Map.get(option_state_by_guid, custom_field["single_select_value"], custom_field["single_select_value"])

          is_binary(custom_field[:single_select_value]) ->
            Map.get(option_state_by_guid, custom_field[:single_select_value], custom_field[:single_select_value])

          is_binary(custom_field["text_value"]) and custom_field["text_value"] != "" ->
            custom_field["text_value"]

          is_binary(custom_field[:text_value]) and custom_field[:text_value] != "" ->
            custom_field[:text_value]

          is_map(custom_field["value"]) and is_binary(custom_field["value"]["option_guid"]) ->
            option_guid = custom_field["value"]["option_guid"]
            Map.get(option_state_by_guid, option_guid, option_guid)

          true ->
            nil
        end
    end
  end

  defp build_state_update_attrs(state_field, option_guid, state_name) do
    attrs = %{
      "custom_fields" => [
        %{
          "guid" => state_field.field_guid,
          "type" => "single_select",
          "single_select_value" => option_guid
        }
      ]
    }

    if Config.settings!().tracker.complete_terminal_tasks do
      Map.put(attrs, "completed_at", completed_at_for_state(state_name))
    else
      attrs
    end
  end

  defp completed_at_for_state(state_name) do
    if terminal_task_state?(state_name) do
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601()
    else
      nil
    end
  end

  defp option_guid_for_state(%{option_guid_by_state: option_guid_by_state}, state_name) do
    normalized_state = normalize_state(state_name)

    case Map.get(option_guid_by_state, normalized_state) do
      option_guid when is_binary(option_guid) and option_guid != "" ->
        {:ok, option_guid}

      _ ->
        {:error, {:unknown_lark_state_option, state_name}}
    end
  end

  defp task_guid(task) when is_map(task) do
    task["guid"] || task[:guid] || task["task_guid"] || task[:task_guid] || task["id"] || task[:id]
  end

  defp synthetic_identifier(task_guid) when is_binary(task_guid) do
    "LT-" <> String.upcase(String.slice(task_guid, 0, 8))
  end

  defp synthetic_identifier(_task_guid), do: "LT-UNKNOWN"

  defp string_value(task, keys) when is_map(task) and is_list(keys) do
    Enum.find_value(keys, fn key ->
      case Map.get(task, key) do
        value when is_binary(value) and value != "" -> value
        _ -> nil
      end
    end)
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp active_task_state?(state_name) do
    normalized_state = normalize_state(state_name)

    Config.settings!().tracker.active_states
    |> Enum.any?(fn configured_state -> normalize_state(configured_state) == normalized_state end)
  end

  defp terminal_task_state?(state_name) do
    normalized_state = normalize_state(state_name)

    Config.settings!().tracker.terminal_states
    |> Enum.any?(fn configured_state -> normalize_state(configured_state) == normalized_state end)
  end

  defp normalize_field_type("single_select"), do: :single_select
  defp normalize_field_type("singleSelect"), do: :single_select
  defp normalize_field_type("select"), do: :single_select
  defp normalize_field_type(other), do: other

  defp normalize_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state_name), do: ""

  defp state_field_cache_key do
    tracker = Config.settings!().tracker
    {@state_field_cache_prefix, tracker.tasklist_guid, normalize_state(tracker.state_field_name)}
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :lark_client_module, Client)
  end
end
