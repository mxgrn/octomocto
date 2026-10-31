defmodule OctomoctoWeb.EchoController do
  use OctomoctoWeb, :controller

  alias Octomocto.Echo.Store
  alias OctomoctoWeb.{EchoLive, Locale, NextGame}

  plug :put_seo

  def show(conn, %{"id" => id}) do
    locale = conn.assigns.locale

    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        index_path: Locale.path(locale, ~p"/echo"),
        settings_path: EchoLive.settings_path(locale, state),
        user_token: user_token(conn.assigns.current_scope),
        # The end screen invites the player to try this game
        next_game: NextGame.pick("echo", id, state.needed > 1),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, gettext("This game does not exist (any more). Start a new one."))
      |> redirect(to: Locale.path(locale, ~p"/echo"))
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, EchoLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
