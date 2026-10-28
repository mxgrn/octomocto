defmodule OctomoctoWeb.SnapController do
  use OctomoctoWeb, :controller

  alias Octomocto.Snap.Store
  alias OctomoctoWeb.{NextGame, SnapLive}

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        settings_path: SnapLive.settings_path(state),
        user_token: user_token(conn.assigns.current_scope),
        # The end screen invites the player to try this game
        next_game: NextGame.pick("snap", id, false),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/snap")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, SnapLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
