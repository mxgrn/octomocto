defmodule OctomoctoWeb.TrainsChannel do
  @moduledoc """
  Connects one browser to a trains game (see `OctomoctoWeb.GameChannel` for
  the join and the rejoin). A browser only watches when the game is full
  or started, or with `"watch": true` in the join params. Changes are
  pushed as `"state"`, `"flip"` and `"decision"` events.
  """
  use Phoenix.Channel

  alias Octomocto.Trains
  alias OctomoctoWeb.{GameChannel, NextGame}

  @game [context: Trains, game: Trains.Game, salt: "trains player", kind: "trains"]

  @impl true
  def join("trains:" <> game_id, params, socket) do
    GameChannel.join(game_id, params, socket, @game)
  end

  @impl true
  def handle_in("flip", %{"cell" => cell, "value" => value}, socket)
      when value in [0, 1] do
    if cell?(cell), do: Trains.flip(socket.assigns.game_id, socket.assigns.player_id, cell, value)
    {:noreply, socket}
  end

  def handle_in("decision", %{"train" => train, "cell" => cell, "exit" => exit}, socket)
      when is_integer(train) do
    if cell?(cell) and cell?(exit) do
      Trains.decide(socket.assigns.game_id, socket.assigns.player_id, train, cell, exit)
    end

    {:noreply, socket}
  end

  def handle_in("finished", %{"seed" => seed, "correct" => correct}, socket) do
    Trains.finish(socket.assigns.game_id, socket.assigns.player_id, seed, correct)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Trains.restart(socket.assigns.game_id, socket.assigns.player_id)
    {:noreply, socket}
  end

  def handle_in("next_game", _params, socket) do
    NextGame.start(socket, @game)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:trains_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  def handle_info({:trains_flip, flip}, socket) do
    push(socket, "flip", flip)
    {:noreply, socket}
  end

  def handle_info({:trains_decision, decision}, socket) do
    push(socket, "decision", decision)
    {:noreply, socket}
  end

  def handle_info(message, socket), do: GameChannel.handle_info(message, socket, @game)

  defp cell?([x, y]) when is_integer(x) and is_integer(y), do: true
  defp cell?(_cell), do: false
end
