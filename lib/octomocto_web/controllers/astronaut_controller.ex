defmodule OctomoctoWeb.AstronautController do
  use OctomoctoWeb, :controller

  alias Octomocto.Astronaut

  plug :put_seo

  def index(conn, _params) do
    render(conn, :index)
  end

  def create(conn, _params) do
    redirect(conn, to: ~p"/astronaut/#{Astronaut.create_game()}")
  end

  def show(conn, %{"id" => id}) do
    if Astronaut.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/astronaut")
    end
  end

  defp put_seo(conn, _opts) do
    merge_assigns(conn,
      page_title: "Station Escape: Multiplayer Space Race",
      page_description:
        "Race your friends to the escape pod on a space station that spins while you play. A free multiplayer maze game in your browser."
    )
  end

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
