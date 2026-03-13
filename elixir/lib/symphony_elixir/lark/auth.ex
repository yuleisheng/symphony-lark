defmodule SymphonyElixir.Lark.Auth do
  @moduledoc """
  Handles tenant access token exchange and caching for Lark Open Platform requests.
  """

  alias SymphonyElixir.Config

  @cache_key {__MODULE__, :tenant_access_token}
  @refresh_skew_seconds 60

  @type token_cache :: %{
          token: String.t(),
          expires_at_unix: pos_integer()
        }

  @spec tenant_access_token(keyword()) :: {:ok, String.t()} | {:error, term()}
  def tenant_access_token(opts \\ []) do
    case cached_token(Keyword.get(opts, :now_unix, System.system_time(:second))) do
      {:ok, token} ->
        {:ok, token}

      :stale ->
        fetch_and_cache_token(opts)
    end
  end

  @spec clear_cache() :: :ok
  def clear_cache do
    :persistent_term.erase(@cache_key)
    :ok
  end

  defp cached_token(now_unix) when is_integer(now_unix) do
    case :persistent_term.get(@cache_key, nil) do
      %{token: token, expires_at_unix: expires_at_unix}
      when is_binary(token) and is_integer(expires_at_unix) and expires_at_unix > now_unix + @refresh_skew_seconds ->
        {:ok, token}

      _ ->
        :stale
    end
  end

  defp fetch_and_cache_token(opts) do
    request_fun = Keyword.get(opts, :request_fun, &request_tenant_access_token/1)
    now_unix = Keyword.get(opts, :now_unix, System.system_time(:second))

    with %{app_id: app_id, app_secret: app_secret} <- Config.settings!().tracker,
         true <- is_binary(app_id) and app_id != "",
         true <- is_binary(app_secret) and app_secret != "",
         {:ok, response} <- request_fun.(%{app_id: app_id, app_secret: app_secret}),
         {:ok, token, expires_in_seconds} <- normalize_token_response(response) do
      :persistent_term.put(@cache_key, %{
        token: token,
        expires_at_unix: now_unix + expires_in_seconds
      })

      {:ok, token}
    else
      false ->
        {:error, :missing_lark_app_credentials}

      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, {:unexpected_lark_auth_response, other}}
    end
  end

  defp request_tenant_access_token(%{app_id: app_id, app_secret: app_secret}) do
    tracker = Config.settings!().tracker

    request =
      Req.new(
        method: :post,
        url: normalize_endpoint(tracker.endpoint) <> "/open-apis/auth/v3/tenant_access_token/internal",
        json: %{
          "app_id" => app_id,
          "app_secret" => app_secret
        },
        headers: [{"content-type", "application/json"}]
      )

    case Req.request(request) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        {:error, {:lark_auth_http_status, status, body}}

      {:error, reason} ->
        {:error, {:lark_auth_request_failed, reason}}
    end
  end

  defp normalize_token_response(%{
         "code" => 0,
         "tenant_access_token" => token,
         "expire" => expires_in_seconds
       })
       when is_binary(token) and is_integer(expires_in_seconds) and expires_in_seconds > 0 do
    {:ok, token, expires_in_seconds}
  end

  defp normalize_token_response(%{
         "code" => 0,
         "tenant_access_token" => token,
         "expire" => expires_in_seconds
       })
       when is_binary(token) and is_binary(expires_in_seconds) do
    case Integer.parse(expires_in_seconds) do
      {parsed, ""} when parsed > 0 -> {:ok, token, parsed}
      _ -> {:error, {:unexpected_lark_auth_response, expires_in_seconds}}
    end
  end

  defp normalize_token_response(%{"code" => code, "msg" => message} = body) do
    {:error, {:lark_auth_error, code, message, body}}
  end

  defp normalize_token_response(other), do: {:error, {:unexpected_lark_auth_response, other}}

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    endpoint
    |> String.trim()
    |> String.trim_trailing("/")
  end
end
