defmodule OctomoctoWeb.MemoryController do
  use OctomoctoWeb, :controller

  alias Octomocto.Memory.Store
  alias OctomoctoWeb.MemoryLive

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        settings_path: MemoryLive.settings_path(state),
        user_token: user_token(conn.assigns.current_scope),
        banner: MemoryLive.banner(conn.query_params),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      # Keeps the link source, so that the Memory page can show its banner
      |> redirect(to: ~p"/memory?#{Map.take(conn.query_params, ["utm_source"])}")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, MemoryLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
