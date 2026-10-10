defmodule OctomoctoWeb.SchulteController do
  use OctomoctoWeb, :controller

  alias Octomocto.Schulte

  plug :put_seo

  def index(conn, params) do
    {board, mode, players} = settings(params)
    leaderboard = Schulte.leaderboard(%{"type" => board, "mode" => mode, "players" => players})
    render(conn, :index, board: board, mode: mode, players: players, leaderboard: leaderboard)
  end

  def create(conn, params) do
    {board, mode, players} = settings(params)
    # Not String.to_existing_atom/1: in dev, the atom can be missing until
    # the Schulte.Game module is loaded
    layout = if board == "random", do: :random, else: :classic
    mode = if mode == "normal", do: :normal, else: :easy
    id = Schulte.create_game(layout, mode, players)
    redirect(conn, to: ~p"/schulte/#{id}")
  end

  def show(conn, %{"id" => id}) do
    if Schulte.game_exists?(id) do
      render(conn, :show,
        id: id,
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/schulte")
    end
  end

  # The classic board in the easy mode for one player, when the params do
  # not say otherwise
  defp settings(params) do
    board = if params["board"] == "random", do: "random", else: "classic"
    mode = if params["mode"] == "normal", do: "normal", else: "easy"

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    {board, mode, players}
  end

  defp put_seo(conn, _opts) do
    merge_assigns(conn,
      page_title: "Schulte Table Race: Find Numbers 1–90",
      page_description:
        "Train your focus and speed with a Schulte table. Find the numbers from 1 to 90 in order, alone or in a race with up to 3 friends. Free, in your browser."
    )
  end

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
