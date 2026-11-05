defmodule OctomoctoWeb.NimbleMosaicController do
  use OctomoctoWeb, :controller

  alias Octomocto.NimbleMosaic.Store
  alias OctomoctoWeb.{NextGame, NimbleMosaicLive}

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        settings_path: NimbleMosaicLive.settings_path(state),
        change_settings_path: NimbleMosaicLive.match_path(state),
        user_token: user_token(conn.assigns.current_scope),
        # The end screen invites the player to try this game
        next_game: NextGame.pick("nimble-mosaic", id, state.needed > 1),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/nimble-mosaic")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, NimbleMosaicLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
