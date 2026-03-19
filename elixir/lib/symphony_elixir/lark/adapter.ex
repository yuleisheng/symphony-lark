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
      requested_ids = MapSet.new(ids)

      with {:ok, state_field} <- resolve_state_field(),
           {:ok, open_tasks} <- fetch_tasks_for_completion_state(false, state_field),
           {:ok, completed_tasks} <- fetch_tasks_for_completion_state(true, state_field) do
        tasks_by_id =
          (open_tasks ++ completed_tasks)
          |> dedupe_tasks()
          |> Map.new(&{&1.id, &1})

        {:ok,
         ids
         |> Enum.filter(&MapSet.member?(requested_ids, &1))
         |> Enum.flat_map(fn issue_id ->
           case Map.get(tasks_by_id, issue_id) do
             %Task{} = task -> [task]
             _ -> []
           end
         end)}
      end
    end
  end

  @spec latest_comment(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def latest_comment(task_guid) when is_binary(task_guid) do
    case client_module().list_comments(task_guid) do
      {:ok, comments} when is_list(comments) ->
        {:ok, pick_latest_comment(comments)}

      {:error, reason} ->
        {:error, reason}
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
      hydrate_task_entries(task_entries, state_field)
    end
  end

  defp hydrate_task_entries(task_entries, state_field) when is_list(task_entries) do
    task_entries
    |> Enum.reduce_while({:ok, []}, fn task_guid, {:ok, acc} ->
      case hydrate_task_entry(task_guid, state_field) do
        {:ok, %Task{} = task} ->
          {:cont, {:ok, [task | acc]}}

        :skip ->
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, tasks} -> {:ok, Enum.reverse(tasks)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp hydrate_task_entry(task_entry, state_field) when is_map(task_entry) do
    task = normalize_task(task_entry, state_field)
    task_guid = task_guid(task_entry)

    cond do
      task_has_dispatch_metadata?(task) ->
        {:ok, task}

      is_binary(task_guid) and task_guid != "" ->
        fetch_task_details(task_entry, task_guid, state_field)

      true ->
        :skip
    end
  end

  defp hydrate_task_entry(_task_entry, _state_field), do: :skip

  defp task_has_dispatch_metadata?(%Task{title: title, state: state})
       when is_binary(title) and title != "" and is_binary(state) and state != "" do
    true
  end

  defp task_has_dispatch_metadata?(_task), do: false

  defp fetch_task_details(task_entry, task_guid, state_field) do
    case client_module().get_task(task_guid) do
      {:ok, task} when is_map(task) ->
        {:ok, normalize_task(merge_task_payloads(task_entry, task), state_field)}

      {:ok, other} ->
        {:error, {:unexpected_lark_task_response, task_guid, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp merge_task_payloads(task_summary, task_details)
       when is_map(task_summary) and is_map(task_details) do
    Map.merge(task_summary, task_details, fn
      "custom_fields", summary_value, details_value ->
        prefer_non_empty_list(details_value, summary_value)

      _key, summary_value, details_value ->
        prefer_present_value(details_value, summary_value)
    end)
  end

  defp prefer_non_empty_list(details_value, _summary_value) when is_list(details_value) and details_value != [],
    do: details_value

  defp prefer_non_empty_list(_details_value, summary_value) when is_list(summary_value), do: summary_value
  defp prefer_non_empty_list(details_value, _summary_value), do: details_value

  defp prefer_present_value(details_value, _summary_value)
       when is_binary(details_value) and details_value != "",
       do: details_value

  defp prefer_present_value(details_value, _summary_value)
       when is_list(details_value) and details_value != [],
       do: details_value

  defp prefer_present_value(details_value, _summary_value)
       when is_map(details_value) and map_size(details_value) > 0,
       do: details_value

  defp prefer_present_value(details_value, _summary_value)
       when is_integer(details_value) or is_float(details_value) or is_boolean(details_value),
       do: details_value

  defp prefer_present_value(nil, summary_value), do: summary_value
  defp prefer_present_value("", summary_value), do: summary_value
  defp prefer_present_value([], summary_value), do: summary_value
  defp prefer_present_value(%{}, summary_value), do: summary_value
  defp prefer_present_value(details_value, _summary_value), do: details_value

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

    with :ok <- validate_state_field_type(field_type),
         {:ok, field_guid} <- validate_state_field_guid(custom_field["guid"] || custom_field[:guid], custom_field) do
      {option_guid_by_state, option_state_by_guid} = build_state_option_maps(custom_field)

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
    task
    |> task_custom_fields()
    |> Enum.find(&state_field_guid?(&1, field_guid))
    |> case do
      nil -> nil
      custom_field -> state_name_from_custom_field(custom_field, option_state_by_guid)
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
    non_runnable_states = non_runnable_task_states()

    not MapSet.member?(non_runnable_states, normalized_state) and
      Enum.any?(Config.settings!().tracker.active_states, fn configured_state ->
        normalize_state(configured_state) == normalized_state
      end)
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

  defp validate_state_field_type(:single_select), do: :ok
  defp validate_state_field_type(field_type), do: {:error, {:invalid_lark_state_field_type, field_type}}

  defp validate_state_field_guid(field_guid, _custom_field) when is_binary(field_guid) and field_guid != "",
    do: {:ok, field_guid}

  defp validate_state_field_guid(_field_guid, custom_field),
    do: {:error, {:invalid_lark_state_field_guid, custom_field}}

  defp build_state_option_maps(custom_field) do
    custom_field
    |> state_field_option_entries()
    |> Enum.reduce({%{}, %{}}, &merge_state_option/2)
  end

  defp state_field_option_entries(custom_field) do
    options =
      custom_field["single_select_setting"] ||
        custom_field[:single_select_setting] ||
        custom_field["select_setting"] ||
        custom_field[:select_setting] ||
        %{}

    Map.get(options, "options") || Map.get(options, :options) || []
  end

  defp merge_state_option(option, {guid_by_state, state_by_guid}) do
    case normalize_state_option(option) do
      {:ok, normalized_state, option_guid, option_name} ->
        {
          Map.put(guid_by_state, normalized_state, option_guid),
          Map.put(state_by_guid, option_guid, option_name)
        }

      :error ->
        {guid_by_state, state_by_guid}
    end
  end

  defp normalize_state_option(option) do
    option_name = option["name"] || option[:name]
    option_guid = option["guid"] || option[:guid]

    if is_binary(option_name) and option_name != "" and is_binary(option_guid) and option_guid != "" do
      {:ok, normalize_state(option_name), option_guid, option_name}
    else
      :error
    end
  end

  defp task_custom_fields(task) when is_map(task) do
    task["custom_fields"] || task[:custom_fields] || []
  end

  defp state_field_guid?(custom_field, field_guid) do
    (custom_field["guid"] || custom_field[:guid]) == field_guid
  end

  defp state_name_from_custom_field(custom_field, option_state_by_guid) do
    display_state_name(custom_field) ||
      single_select_state_name(custom_field, option_state_by_guid) ||
      text_state_name(custom_field) ||
      nested_option_state_name(custom_field, option_state_by_guid)
  end

  defp display_state_name(custom_field) do
    present_string(custom_field["display_value"]) || present_string(custom_field[:display_value])
  end

  defp single_select_state_name(custom_field, option_state_by_guid) do
    option_state_name(custom_field["single_select_value"], option_state_by_guid) ||
      option_state_name(custom_field[:single_select_value], option_state_by_guid)
  end

  defp text_state_name(custom_field) do
    present_string(custom_field["text_value"]) || present_string(custom_field[:text_value])
  end

  defp nested_option_state_name(custom_field, option_state_by_guid) do
    case custom_field["value"] do
      %{"option_guid" => option_guid} -> option_state_name(option_guid, option_state_by_guid)
      _ -> nil
    end
  end

  defp option_state_name(option_guid, option_state_by_guid) when is_binary(option_guid) do
    Map.get(option_state_by_guid, option_guid, option_guid)
  end

  defp option_state_name(_option_guid, _option_state_by_guid), do: nil

  defp present_string(value) when is_binary(value) and value != "", do: value
  defp present_string(_value), do: nil

  defp normalize_state(state_name) when is_binary(state_name) do
    state_name
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state_name), do: ""

  defp pick_latest_comment(comments) when is_list(comments) do
    comments
    |> Enum.with_index()
    |> Enum.max_by(&comment_sort_key/1, fn -> nil end)
    |> case do
      {comment, _index} -> comment
      nil -> nil
    end
  end

  defp comment_sort_key({comment, index}) when is_map(comment) do
    {
      comment_timestamp(comment, ["updated_at", "update_time", "updated_msec", "updated_at_msec"]),
      comment_timestamp(comment, ["created_at", "create_time", "created_msec", "created_at_msec"]),
      index
    }
  end

  defp comment_timestamp(comment, keys) do
    Enum.find_value(keys, 0, fn key ->
      case Map.get(comment, key) do
        value when is_integer(value) -> value
        value when is_binary(value) -> parse_sortable_timestamp(value)
        _ -> nil
      end
    end)
  end

  defp parse_sortable_timestamp(value) when is_binary(value) do
    if String.match?(value, ~r/^\d+$/) do
      parse_numeric_timestamp(value)
    else
      parse_iso8601_timestamp(value)
    end
  end

  defp parse_numeric_timestamp(value) do
    case Integer.parse(value) do
      {parsed, ""} -> parsed
      _ -> 0
    end
  end

  defp parse_iso8601_timestamp(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.to_unix(datetime, :millisecond)
      _ -> 0
    end
  end

  defp non_runnable_task_states do
    tracker = Config.settings!().tracker

    [tracker.blocked_state, tracker.review_state]
    |> Enum.map(&normalize_state/1)
    |> MapSet.new()
  end

  defp state_field_cache_key do
    tracker = Config.settings!().tracker
    {@state_field_cache_prefix, tracker.tasklist_guid, normalize_state(tracker.state_field_name)}
  end

  defp client_module do
    Application.get_env(:symphony_elixir, :lark_client_module, Client)
  end
end
