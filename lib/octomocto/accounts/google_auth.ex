defmodule Octomocto.Accounts.GoogleAuth do
  @moduledoc """
  "Continue with Google": the OAuth 2.0 code flow of Google's OpenID Connect.

  We send the user to `authorize_url/2`. Google sends the user back with a
  code, and `fetch_user/2` changes the code for an ID token.

  We do not check the signature of the ID token, because we get it from
  Google's token endpoint over TLS and not from the browser. See
  https://developers.google.com/identity/openid-connect/openid-connect#obtainuserinfo
  """

  @authorize_url "https://accounts.google.com/o/oauth2/v2/auth"
  @token_url "https://oauth2.googleapis.com/token"
  @issuers ["https://accounts.google.com", "accounts.google.com"]

  def enabled?, do: !!(client_id() && client_secret())

  def client_id, do: config()[:client_id]

  @doc "The URL of the Google page where the user picks an account."
  def authorize_url(redirect_uri, state) do
    query =
      URI.encode_query(
        client_id: client_id(),
        redirect_uri: redirect_uri,
        response_type: "code",
        scope: "openid email profile",
        state: state
      )

    @authorize_url <> "?" <> query
  end

  @doc """
  Changes the code from Google for the user data.

  Returns `{:ok, attrs}` or `{:error, :invalid}`.
  """
  def fetch_user(code, redirect_uri) do
    form = [
      code: code,
      client_id: client_id(),
      client_secret: client_secret(),
      redirect_uri: redirect_uri,
      grant_type: "authorization_code"
    ]

    with {:ok, %{status: 200, body: %{"id_token" => id_token}}} <-
           Req.post(@token_url, [form: form, retry: false] ++ (config()[:req_options] || [])),
         {:ok, claims} <- decode(id_token),
         true <- valid?(claims) do
      {:ok,
       %{
         google_id: claims["sub"],
         email: claims["email"],
         name: claims["name"],
         avatar_url: claims["picture"]
       }}
    else
      _ -> {:error, :invalid}
    end
  end

  defp decode(id_token) do
    with [_header, payload, _signature] <- String.split(id_token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false) do
      Jason.decode(json)
    end
  end

  defp valid?(claims) do
    claims["iss"] in @issuers and claims["aud"] == client_id() and
      is_binary(claims["sub"]) and is_binary(claims["email"]) and
      claims["email_verified"] == true
  end

  defp client_secret, do: config()[:client_secret]

  defp config, do: Application.get_env(:octomocto, :google, [])
end
