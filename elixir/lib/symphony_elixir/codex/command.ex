defmodule SymphonyElixir.Codex.Command do
  @moduledoc false

  @shell_metacharacters ["|", "&", ";", "<", ">", "\n", "\r", "`", "$("]
  @helper_commands MapSet.new(["command", "env", "exec"])

  @spec validate_local(String.t()) :: :ok | {:error, {:codex_command_not_found, String.t(), String.t()}}
  def validate_local(command) when is_binary(command) do
    case executable_candidate(command) do
      {:ok, executable} ->
        if executable_available?(executable) do
          :ok
        else
          {:error, {:codex_command_not_found, executable, command}}
        end

      :skip ->
        :ok
    end
  end

  @spec format_not_found_error(String.t(), String.t()) :: String.t()
  def format_not_found_error(executable, command) when is_binary(executable) and is_binary(command) do
    "Codex launcher `#{executable}` is not available in PATH for this Symphony process. " <>
      "Symphony launches local runs with `#{command}`. Put Codex on PATH before starting Symphony, " <>
      "or set `codex.command` to an absolute path."
  end

  defp executable_candidate(command) when is_binary(command) do
    trimmed = String.trim(command)

    cond do
      trimmed == "" ->
        :skip

      String.contains?(trimmed, @shell_metacharacters) ->
        :skip

      true ->
        trimmed
        |> OptionParser.split()
        |> first_direct_executable()
    end
  rescue
    _ -> :skip
  end

  defp first_direct_executable([]), do: :skip

  defp first_direct_executable([token | _rest]) do
    cond do
      env_assignment?(token) ->
        :skip

      MapSet.member?(@helper_commands, token) ->
        :skip

      true ->
        {:ok, token}
    end
  end

  defp executable_available?(executable) when is_binary(executable) do
    cond do
      executable == "" ->
        false

      Path.type(executable) == :absolute ->
        File.exists?(executable)

      String.contains?(executable, "/") ->
        true

      true ->
        not is_nil(System.find_executable(executable))
    end
  end

  defp env_assignment?(token) when is_binary(token) do
    case String.split(token, "=", parts: 2) do
      [name, _value] ->
        String.match?(name, ~r/^[A-Za-z_][A-Za-z0-9_]*$/)

      _ ->
        false
    end
  end
end
