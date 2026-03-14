defmodule SymphonyElixir.Tracker.Memory do
  @moduledoc """
  In-memory tracker adapter used for tests and local development.
  """

  @behaviour SymphonyElixir.Tracker

  alias SymphonyElixir.Tracker.Task

  @spec fetch_candidate_issues() :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_candidate_issues do
    {:ok, issue_entries()}
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_issues_by_states(state_names) do
    normalized_states =
      state_names
      |> Enum.map(&normalize_state/1)
      |> MapSet.new()

    {:ok,
     Enum.filter(issue_entries(), fn %Task{state: state} ->
       MapSet.member?(normalized_states, normalize_state(state))
     end)}
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [Task.t()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    wanted_ids = MapSet.new(issue_ids)

    {:ok,
     Enum.filter(issue_entries(), fn %Task{id: id} ->
       MapSet.member?(wanted_ids, id)
     end)}
  end

  @spec list_comments(String.t()) :: {:ok, [map()]} | {:error, term()}
  def list_comments(issue_id) when is_binary(issue_id) do
    comments =
      Application.get_env(:symphony_elixir, :memory_tracker_comments, %{})
      |> Map.get(issue_id, [])

    {:ok, comments}
  end

  @spec latest_comment(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def latest_comment(issue_id) when is_binary(issue_id) do
    with {:ok, comments} <- list_comments(issue_id) do
      {:ok, List.last(comments)}
    end
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    comments =
      Application.get_env(:symphony_elixir, :memory_tracker_comments, %{})
      |> Map.update(issue_id, [%{"content" => body}], fn existing ->
        existing ++ [%{"content" => body}]
      end)

    Application.put_env(:symphony_elixir, :memory_tracker_comments, comments)
    send_event({:memory_tracker_comment, issue_id, body})
    :ok
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    send_event({:memory_tracker_state_update, issue_id, state_name})
    :ok
  end

  defp configured_issues do
    Application.get_env(:symphony_elixir, :memory_tracker_issues, [])
  end

  defp issue_entries do
    Enum.filter(configured_issues(), &match?(%Task{}, &1))
  end

  defp send_event(message) do
    case Application.get_env(:symphony_elixir, :memory_tracker_recipient) do
      pid when is_pid(pid) -> send(pid, message)
      _ -> :ok
    end
  end

  defp normalize_state(state) when is_binary(state) do
    state
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_state(_state), do: ""
end
