defmodule OctomoctoWeb.SchulteController do
  use OctomoctoWeb, :controller

  alias Octomocto.Schulte

  def index(conn, _params) do
    render(conn, :index)
  end

  def create(conn, params) do
    layout = if params["layout"] == "classic", do: :classic, else: :random
    redirect(conn, to: ~p"/schulte/#{Schulte.create_game(layout)}")
  end

  def show(conn, %{"id" => id}) do
    if Schulte.game_exists?(id) do
      render(conn, :show, id: id)
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/schulte")
    end
  end
end
