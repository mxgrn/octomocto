defmodule OctomoctoWeb.AstronautController do
  use OctomoctoWeb, :controller

  alias Octomocto.Astronaut

  def index(conn, _params) do
    render(conn, :index)
  end

  def create(conn, _params) do
    redirect(conn, to: ~p"/astronaut/#{Astronaut.create_game()}")
  end

  def show(conn, %{"id" => id}) do
    if Astronaut.game_exists?(id) do
      render(conn, :show, id: id)
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/astronaut")
    end
  end
end
