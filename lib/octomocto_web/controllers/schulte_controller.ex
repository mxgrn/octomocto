defmodule OctomoctoWeb.SchulteController do
  use OctomoctoWeb, :controller

  alias Octomocto.Schulte

  def index(conn, params) do
    {board, players} = settings(params)
    leaderboard = Schulte.leaderboard(%{"type" => board, "players" => players})
    render(conn, :index, board: board, players: players, leaderboard: leaderboard)
  end

  def create(conn, params) do
    {board, players} = settings(params)
    # Not String.to_existing_atom/1: in dev, the atom can be missing until
    # the Schulte.Game module is loaded
    layout = if board == "random", do: :random, else: :classic
    id = Schulte.create_game(layout, players)
    redirect(conn, to: ~p"/schulte/#{id}")
  end

  def show(conn, %{"id" => id}) do
    if Schulte.game_exists?(id) do
      render(conn, :show, id: id, user_token: user_token(conn.assigns.current_scope))
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/schulte")
    end
  end

  # The classic board for one player, when the params do not say otherwise
  defp settings(params) do
    board = if params["board"] == "random", do: "random", else: "classic"

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    {board, players}
  end

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
