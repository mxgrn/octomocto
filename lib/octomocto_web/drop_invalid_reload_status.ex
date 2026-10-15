defmodule OctomoctoWeb.DropInvalidReloadStatus do
  @moduledoc """
  Removes a LiveView reload status cookie that has an invalid token.

  LiveView sends a 500 for a request with such a cookie, so any client can
  cause an error (see phoenixframework/phoenix_live_view#4475). Remove this
  plug when LiveView ignores invalid tokens.
  """

  import Plug.Conn

  @cookie "__phoenix_reload_status__"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    with %{@cookie => token} <- conn.req_cookies,
         {:error, _reason} <- verify(conn, token) do
      %{
        conn
        | req_cookies: Map.delete(conn.req_cookies, @cookie),
          cookies: Map.delete(conn.cookies, @cookie)
      }
      |> delete_resp_cookie(@cookie)
    else
      _ -> conn
    end
  end

  # Phoenix.LiveView.Static is internal, but it verifies the token the same
  # way as LiveView does when it renders the page.
  defp verify(conn, token) do
    Phoenix.LiveView.Static.verify_token(Phoenix.Controller.endpoint_module(conn), token)
  end
end
