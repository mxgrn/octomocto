defmodule OctomoctoWeb.SetGameController do
  use OctomoctoWeb, :controller

  alias Octomocto.SetGame

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if SetGame.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/set")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, OctomoctoWeb.SetGameLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
