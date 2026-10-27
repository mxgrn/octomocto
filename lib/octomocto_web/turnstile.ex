defmodule OctomoctoWeb.Turnstile do
  @moduledoc """
  Verifies the token of the Cloudflare Turnstile widget ("I'm not a robot")
  on the forms that send a sign-in link.

  The check is on only when both keys are set. They are set only in prod,
  from TURNSTILE_SITE_KEY and TURNSTILE_SECRET_KEY.

  See https://developers.cloudflare.com/turnstile/get-started/server-side-validation/
  """

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  # The name of the hidden input that the widget adds to the form
  @response_param "cf-turnstile-response"

  def enabled?, do: !!(site_key() && secret_key())

  def site_key, do: config()[:site_key]

  @doc """
  Verifies the widget token in the form params.

  Returns `:ok` when the token is valid or when the check is off,
  otherwise `{:error, :turnstile}`.
  """
  def verify(params) do
    token = params[@response_param]

    cond do
      !enabled?() -> :ok
      is_binary(token) and token != "" -> request(token)
      true -> {:error, :turnstile}
    end
  end

  defp request(token) do
    case Req.post(@verify_url, form: [secret: secret_key(), response: token]) do
      {:ok, %{status: 200, body: %{"success" => true}}} -> :ok
      _ -> {:error, :turnstile}
    end
  end

  defp secret_key, do: config()[:secret_key]

  defp config, do: Application.get_env(:octomocto, :turnstile, [])
end
