defmodule Octomocto.Penguin.Game do
  @moduledoc """
  One multiplayer penguin maze. It owns the maze, the rotation timer and the
  penguins, and broadcasts each change on the `"penguin_game:<id>"` PubSub
  topic as `{:penguin_state, state}`.

  Each player is bound to the process that joined (a channel). The penguin
  is removed when that process stops. The game stops after some time with
  no players.
  """
  use GenServer, restart: :temporary

  alias Octomocto.Penguin.Maze

  @size 9
  @start {0, 0}
  @fish {@size - 1, @size - 1}
  @round_pause_ms 2500
  @idle_timeout_ms :timer.minutes(5)

  @colors [
    {"pink", "#ec4899"},
    {"sky", "#0ea5e9"},
    {"lime", "#65a30d"},
    {"amber", "#d97706"},
    {"violet", "#8b5cf6"},
    {"red", "#dc2626"},
    {"teal", "#0d9488"},
    {"indigo", "#4f46e5"}
  ]

  def start_link(id) do
    GenServer.start_link(__MODULE__, id, name: via(id))
  end

  def via(id), do: {:via, Registry, {Octomocto.Penguin.Registry, id}}

  def topic(id), do: "penguin_game:" <> id

  @impl true
  def init(id) do
    schedule_rotation()
    schedule_idle_check()

    {:ok,
     %{
       id: id,
       passages: Maze.generate(@size),
       round: 1,
       quarter_turns: 0,
       winner: nil,
       players: %{}
     }}
  end

  @impl true
  def handle_call({:join, pid}, _from, state) do
    Process.monitor(pid)
    player_id = Integer.to_string(System.unique_integer([:positive]))
    {color_name, color} = pick_color(state.players)

    player = %{
      pid: pid,
      color: color,
      color_name: color_name,
      pos: @start,
      facing: :south,
      score: 0,
      joined_at: System.monotonic_time()
    }

    state = put_in(state.players[player_id], player)
    broadcast(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  @impl true
  def handle_cast({:move, player_id, dir}, state) do
    case state.players do
      %{^player_id => player} when state.winner == nil ->
        {:noreply, state |> move(player_id, player, dir) |> tap(&broadcast/1)}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:rotate, state) do
    schedule_rotation()
    state = %{state | quarter_turns: state.quarter_turns + Enum.random([1, -1])}
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:new_round, state) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | pos: @start, facing: :south}} end)

    state = %{
      state
      | passages: Maze.generate(@size),
        round: state.round + 1,
        winner: nil,
        players: players
    }

    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    players = state.players |> Enum.reject(fn {_id, p} -> p.pid == pid end) |> Map.new()
    state = %{state | players: players}
    broadcast(state)
    {:noreply, state}
  end

  def handle_info(:idle_check, state) do
    if state.players == %{} do
      {:stop, :normal, state}
    else
      schedule_idle_check()
      {:noreply, state}
    end
  end

  defp move(state, player_id, player, dir) do
    player = %{player | facing: dir}

    player =
      if Maze.can_move?(state.passages, player.pos, dir) do
        %{player | pos: Maze.step(player.pos, dir)}
      else
        player
      end

    if player.pos == @fish do
      Process.send_after(self(), :new_round, @round_pause_ms)
      player = %{player | score: player.score + 1}
      %{state | winner: player_id, players: Map.put(state.players, player_id, player)}
    else
      %{state | players: Map.put(state.players, player_id, player)}
    end
  end

  # Prefer a color that no penguin has. Reuse colors when all are taken.
  defp pick_color(players) do
    taken = players |> Map.values() |> Enum.map(& &1.color)

    case Enum.reject(@colors, fn {_name, color} -> color in taken end) do
      [] -> Enum.random(@colors)
      free -> Enum.random(free)
    end
  end

  defp schedule_rotation do
    Process.send_after(self(), :rotate, Enum.random(3000..7000))
  end

  defp schedule_idle_check do
    Process.send_after(self(), :idle_check, @idle_timeout_ms)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:penguin_state, public(state)})
  end

  # The state that clients see, ready to encode as JSON.
  defp public(state) do
    {fish_x, fish_y} = @fish

    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.joined_at end)
      |> Enum.map(fn {id, p} ->
        {x, y} = p.pos

        %{
          id: id,
          color: p.color,
          color_name: p.color_name,
          x: x,
          y: y,
          facing: p.facing,
          score: p.score
        }
      end)

    %{
      size: @size,
      passages: for({{x1, y1}, {x2, y2}} <- state.passages, do: [x1, y1, x2, y2]),
      fish: [fish_x, fish_y],
      round: state.round,
      quarter_turns: state.quarter_turns,
      winner: state.winner,
      players: players
    }
  end
end
