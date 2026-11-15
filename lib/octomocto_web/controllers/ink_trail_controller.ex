defmodule OctomoctoWeb.InkTrailController do
  use OctomoctoWeb, :controller

  alias Octomocto.InkTrail.Store
  alias OctomoctoWeb.{InkTrailLive, Locale, NextGame}

  plug :put_seo

  def show(conn, %{"id" => id}) do
    locale = conn.assigns.locale

    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        settings_path: InkTrailLive.settings_path(locale, state),
        user_token: user_token(conn.assigns.current_scope),
        # The end screen invites the player to try this game
        next_game: NextGame.pick("ink-trail", id, false),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, gettext("This game does not exist (any more). Start a new one."))
      |> redirect(to: Locale.path(locale, ~p"/ink-trail"))
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, InkTrailLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
