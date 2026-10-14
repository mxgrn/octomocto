defmodule OctomoctoWeb.TrainsController do
  use OctomoctoWeb, :controller

  alias Octomocto.Trains

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if Trains.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/trains")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, OctomoctoWeb.TrainsLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
