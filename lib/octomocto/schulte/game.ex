defmodule Octomocto.Schulte.Game do
  @moduledoc """
  One multiplayer Schulte table: a random field with the numbers 1 to 90
  (see `Octomocto.Schulte.Layout`).
  The first player to click the next number gets a point. The game owns the
  field and the players, and broadcasts each change on the
  `"schulte_game:<id>"` PubSub topic as `{:schulte_state, state}`.

  Each player is bound to the process that joined (a channel). The player
  is removed when that process stops. The game stops after some time with
  no players.
  """
  use GenServer, restart: :temporary

  alias Octomocto.Schulte.Layout

  @total 90
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

  def via(id), do: {:via, Registry, {Octomocto.Schulte.Registry, id}}

  def topic(id), do: "schulte_game:" <> id

  @impl true
  def init(id) do
    schedule_idle_check()
    {:ok, new_field(%{id: id, players: %{}})}
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
      score: 0,
      joined_at: System.monotonic_time()
    }

    state = put_in(state.players[player_id], player)
    broadcast(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  @impl true
  def handle_cast({:pick, player_id, number}, %{next: number} = state)
      when is_map_key(state.players, player_id) do
    state =
      state
      |> update_in([:players, player_id, :score], &(&1 + 1))
      |> Map.update!(:found_by, &Map.put(&1, number, player_id))
      |> Map.put(:next, number + 1)

    broadcast(state)
    {:noreply, state}
  end

  def handle_cast({:pick, _player_id, _number}, state), do: {:noreply, state}

  def handle_cast(:restart, state) when state.next > @total do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0}} end)
    state = new_field(%{state | players: players})
    broadcast(state)
    {:noreply, state}
  end

  def handle_cast(:restart, state), do: {:noreply, state}

  @impl true
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

  defp new_field(state) do
    regions =
      Enum.zip_with(Enum.shuffle(1..@total), Layout.generate(@total), &Map.put(&2, :number, &1))

    Map.merge(state, %{regions: regions, next: 1, found_by: %{}})
  end

  # Prefer a color that no player has. Reuse colors when all are taken.
  defp pick_color(players) do
    taken = players |> Map.values() |> Enum.map(& &1.color)

    case Enum.reject(@colors, fn {_name, color} -> color in taken end) do
      [] -> Enum.random(@colors)
      free -> Enum.random(free)
    end
  end

  defp schedule_idle_check do
    Process.send_after(self(), :idle_check, @idle_timeout_ms)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:schulte_state, public(state)})
  end

  # The state that clients see, ready to encode as JSON.
  defp public(state) do
    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.joined_at end)
      |> Enum.map(fn {id, p} ->
        %{id: id, color: p.color, color_name: p.color_name, score: p.score}
      end)

    %{
      board: Tuple.to_list(Layout.size()),
      total: @total,
      next: state.next,
      cells: Enum.map(state.regions, &Map.put(&1, :found_by, state.found_by[&1.number])),
      players: players
    }
  end
end
