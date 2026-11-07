defmodule OctomoctoWeb.AfterglowController do
  use OctomoctoWeb, :controller

  alias Octomocto.Afterglow.{Store, TurnStore}
  alias OctomoctoWeb.{AfterglowLive, NextGame}

  plug :put_seo

  # A single-player game, or a game with turns
  def show(conn, %{"id" => id}) do
    cond do
      Store.read(id) ->
        render(conn, :show,
          id: id,
          settings_path: ~p"/afterglow",
          user_token: user_token(conn.assigns.current_scope),
          # The end screen invites the player to try this game
          next_game: NextGame.pick("afterglow", id, false),
          noindex: true
        )

      state = TurnStore.read(id) ->
        render(conn, :show_turns,
          id: id,
          settings_path: AfterglowLive.settings_path(state),
          change_settings_path: AfterglowLive.match_path(state),
          user_token: user_token(conn.assigns.current_scope),
          next_game: NextGame.pick("afterglow", id, true),
          noindex: true
        )

      true ->
        conn
        |> put_flash(:error, "This game does not exist (any more). Start a new one.")
        |> redirect(to: ~p"/afterglow")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, AfterglowLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
