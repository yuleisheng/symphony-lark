defmodule SymphonyElixir.Config do
  @moduledoc """
  Runtime configuration loaded from `WORKFLOW.md`.
  """

  alias SymphonyElixir.{Codex.Command, Config.Schema}
  alias SymphonyElixir.Workflow

  @default_prompt_template """
  You are working on a Lark task.

  Identifier: {{ task.identifier }}
  Task GUID: {{ task.id }}
  Title: {{ task.title }}

  Body:
  {% if task.description %}
  {{ task.description }}
  {% else %}
  No description provided.
  {% endif %}

  Lark API rules:
  - Use full Task v2 paths under /open-apis/task/v2/..., never relative paths like tasks/... or comments.
  - When a path needs the task GUID, use {{ task.id }}, never {{ task.identifier }}.
  - Update workflow status through task.custom_fields with update_fields ["custom_fields"], not task.status.
  """

  @type codex_runtime_settings :: %{
          approval_policy: String.t() | map(),
          thread_sandbox: String.t(),
          turn_sandbox_policy: map()
        }

  @spec settings() :: {:ok, Schema.t()} | {:error, term()}
  def settings do
    case Workflow.current() do
      {:ok, %{config: config}} when is_map(config) ->
        Schema.parse(config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec settings!() :: Schema.t()
  def settings! do
    case settings() do
      {:ok, settings} ->
        settings

      {:error, reason} ->
        raise ArgumentError, message: format_config_error(reason)
    end
  end

  @spec max_concurrent_agents_for_state(term()) :: pos_integer()
  def max_concurrent_agents_for_state(state_name) when is_binary(state_name) do
    config = settings!()

    Map.get(
      config.agent.max_concurrent_agents_by_state,
      Schema.normalize_issue_state(state_name),
      config.agent.max_concurrent_agents
    )
  end

  def max_concurrent_agents_for_state(_state_name), do: settings!().agent.max_concurrent_agents

  @spec codex_turn_sandbox_policy(Path.t() | nil) :: map()
  def codex_turn_sandbox_policy(workspace \\ nil) do
    case Schema.resolve_runtime_turn_sandbox_policy(settings!(), workspace) do
      {:ok, policy} ->
        policy

      {:error, reason} ->
        raise ArgumentError, message: "Invalid codex turn sandbox policy: #{inspect(reason)}"
    end
  end

  @spec workflow_prompt() :: String.t()
  def workflow_prompt do
    case Workflow.current() do
      {:ok, %{prompt_template: prompt}} ->
        if String.trim(prompt) == "", do: @default_prompt_template, else: prompt

      _ ->
        @default_prompt_template
    end
  end

  @spec server_port() :: non_neg_integer() | nil
  def server_port do
    case Application.get_env(:symphony_elixir, :server_port_override) do
      port when is_integer(port) and port >= 0 -> port
      _ -> settings!().server.port
    end
  end

  @spec validate!() :: :ok | {:error, term()}
  def validate! do
    with {:ok, workflow} <- Workflow.current(),
         {:ok, settings} <- Schema.parse(workflow.config) do
      validate_semantics(settings, workflow.config)
    end
  end

  @spec format_validation_error(term()) :: String.t()
  def format_validation_error(reason) do
    case reason do
      :missing_lark_app_id ->
        "Lark app ID missing. Set `tracker.app_id` or export `LARK_APP_ID`."

      :missing_lark_app_secret ->
        "Lark app secret missing. Set `tracker.app_secret` or export `LARK_APP_SECRET`."

      :missing_lark_tasklist_guid ->
        "Lark tasklist GUID missing. Set `tracker.tasklist_guid` or export `LARK_TASKLIST_GUID`."

      :missing_lark_state_field_name ->
        "Lark state field name missing. Set `tracker.state_field_name`."

      :missing_symphony_workspace_root ->
        "Workspace root missing. Set `workspace.root` or export `SYMPHONY_WORKSPACE_ROOT`."

      :missing_symphony_repo_root ->
        "Repository root missing. Export `SYMPHONY_REPO_ROOT` for the default repo materialization hook."

      {:codex_command_not_found, executable, command} ->
        Command.format_not_found_error(executable, command)

      other ->
        format_config_error(other)
    end
  end

  @spec codex_runtime_settings(Path.t() | nil, keyword()) ::
          {:ok, codex_runtime_settings()} | {:error, term()}
  def codex_runtime_settings(workspace \\ nil, opts \\ []) do
    with {:ok, settings} <- settings() do
      with {:ok, turn_sandbox_policy} <-
             Schema.resolve_runtime_turn_sandbox_policy(settings, workspace, opts) do
        {:ok,
         %{
           approval_policy: settings.codex.approval_policy,
           thread_sandbox: settings.codex.thread_sandbox,
           turn_sandbox_policy: turn_sandbox_policy
         }}
      end
    end
  end

  defp validate_semantics(settings, workflow_config) do
    cond do
      blank_string?(settings.tracker.app_id) ->
        {:error, :missing_lark_app_id}

      blank_string?(settings.tracker.app_secret) ->
        {:error, :missing_lark_app_secret}

      blank_string?(settings.tracker.tasklist_guid) ->
        {:error, :missing_lark_tasklist_guid}

      blank_string?(settings.tracker.state_field_name) ->
        {:error, :missing_lark_state_field_name}

      missing_workspace_root?(settings.workspace.root, workflow_config) ->
        {:error, :missing_symphony_workspace_root}

      missing_repo_root?(workflow_config) ->
        {:error, :missing_symphony_repo_root}

      true ->
        validate_local_codex_command(settings)
    end
  end

  defp validate_local_codex_command(%{worker: %{ssh_hosts: ssh_hosts}, codex: %{command: command}}) do
    ssh_hosts =
      ssh_hosts
      |> List.wrap()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if ssh_hosts == [] do
      Command.validate_local(command)
    else
      :ok
    end
  end

  defp blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_string?(_value), do: true

  defp missing_workspace_root?(workspace_root, workflow_config) do
    blank_string?(workspace_root) or
      explicit_blank_workspace_root?(workflow_config) or
      missing_env_reference?(get_in(workflow_config, ["workspace", "root"]), "SYMPHONY_WORKSPACE_ROOT")
  end

  defp missing_repo_root?(workflow_config) do
    case get_in(workflow_config, ["hooks", "after_create"]) do
      value when is_binary(value) ->
        String.contains?(value, "$SYMPHONY_REPO_ROOT") and blank_string?(System.get_env("SYMPHONY_REPO_ROOT"))

      _ ->
        false
    end
  end

  defp explicit_blank_workspace_root?(workflow_config) do
    case get_in(workflow_config, ["workspace", "root"]) do
      value when is_binary(value) -> String.trim(value) == ""
      _ -> false
    end
  end

  defp missing_env_reference?(value, expected_env_name) when is_binary(value) do
    case config_env_reference_name(String.trim(value)) do
      {:ok, ^expected_env_name} ->
        case System.get_env(expected_env_name) do
          nil -> true
          "" -> true
          _ -> false
        end

      _ ->
        false
    end
  end

  defp missing_env_reference?(_value, _expected_env_name), do: false

  defp config_env_reference_name("$" <> env_name) do
    if String.match?(env_name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/) do
      {:ok, env_name}
    else
      :error
    end
  end

  defp config_env_reference_name(_value), do: :error

  defp format_config_error(reason) do
    case reason do
      {:invalid_workflow_config, message} ->
        "Invalid WORKFLOW.md config: #{message}"

      {:missing_workflow_file, path, raw_reason} ->
        "Missing WORKFLOW.md at #{path}: #{inspect(raw_reason)}"

      {:workflow_parse_error, raw_reason} ->
        "Failed to parse WORKFLOW.md: #{inspect(raw_reason)}"

      :workflow_front_matter_not_a_map ->
        "Failed to parse WORKFLOW.md: workflow front matter must decode to a map"

      other ->
        "Invalid WORKFLOW.md config: #{inspect(other)}"
    end
  end
end
