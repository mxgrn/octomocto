defmodule OctomoctoWeb.AstronautController do
  @moduledoc """
  The astronaut maze. It is the penguin maze with a space theme, so it uses
  the `Octomocto.Penguin` games and the penguin channel.
  """
  use OctomoctoWeb, :controller

  alias Octomocto.Penguin

  def index(conn, _params) do
    render(conn, :index)
  end

  def create(conn, _params) do
    redirect(conn, to: ~p"/astronaut/#{Penguin.create_game()}")
  end

  def show(conn, %{"id" => id}) do
    if Penguin.game_exists?(id) do
      render(conn, :show, id: id)
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/astronaut")
    end
  end
end
