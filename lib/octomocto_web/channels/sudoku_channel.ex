defmodule OctomoctoWeb.SudokuChannel do
  @moduledoc """
  Connects one browser to a sudoku game (see `OctomoctoWeb.GameChannel`
  for the join and the rejoin). Each change of the game is pushed as a
  `"state"` event. The reply to a `"place"` tells if the digit is
  correct, so that the browser can shake a wrong digit.
  """
  use Phoenix.Channel

  alias Octomocto.Sudoku
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Sudoku, game: Sudoku.Game, salt: "sudoku player", kind: "sudoku"]

  @impl true
  def join("sudoku:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("place", %{"cell" => cell, "digit" => digit}, socket)
      when is_integer(cell) and is_integer(digit) do
    result = Sudoku.place(socket.assigns.game_id, socket.assigns.player_id, cell, digit)
    {:reply, {:ok, %{result: result}}, socket}
  end

  def handle_in("restart", _params, socket) do
    Sudoku.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:sudoku_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)
end
