defmodule OctomoctoWeb.SchulteLive do
  use OctomoctoWeb, :live_view

  import OctomoctoWeb.SchulteHTML

  alias Octomocto.Schulte

  def mount(_params, _session, socket) do
    {:ok, assign(socket, seo())}
  end

  @doc "The title and the description of the Schulte pages, for search engines."
  def seo do
    [
      page_title: "Schulte Table Race: Find Numbers 1–90",
      page_description:
        "Train your focus and speed with a Schulte table. Find the numbers from 1 to 90 in order, alone or in a race with up to 3 friends. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    {board, mode, players} = settings(params)
    filter = %{"type" => board, "mode" => mode, "players" => players}

    {:noreply,
     assign(socket,
       board: board,
       mode: mode,
       players: players,
       leaderboard: Schulte.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_event("new_game", _params, socket) do
    %{board: board, mode: mode, players: players} = socket.assigns
    # Not String.to_existing_atom/1: in dev, the atom can be missing until
    # the Schulte.Game module is loaded
    layout = if board == "random", do: :random, else: :classic
    mode = if mode == "normal", do: :normal, else: :easy
    id = Schulte.create_game(layout, mode, players)
    {:noreply, redirect(socket, to: ~p"/schulte/#{id}")}
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

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Schulte.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil
end
