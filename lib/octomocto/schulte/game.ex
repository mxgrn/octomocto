defmodule Octomocto.Schulte.Game do
  @moduledoc """
  One multiplayer Schulte table: a field with the numbers 1 to 90. The
  layout is `:random` (a new board for each field, see
  `Octomocto.Schulte.Layout`) or `:classic` (always the same board, see
  `Octomocto.Schulte.Classic`). The numbers are in a random order.
  The mode is `:easy` (the client hides the found numbers) or `:normal`
  (the found numbers stay on the board).
  The first player to click the next number gets a point. The game owns the
  field and the players, and broadcasts each change on the
  `"schulte_game:<id>"` PubSub topic as `{:schulte_state, state}`.

  The game is for a set number of players (`needed`). The clock of each
  field starts when the game has all its players, and nobody can pick a
  number before that. The field starts after a countdown. A process that joins a full game only watches.

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. When all numbers are found with all players still
  in the game, the game saves the result of each player (see
  `Octomocto.Schulte.save_results/4`). The game stops after some time with
  no players.

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.Schulte.Store` after each change. When its node stops, the
  game starts again on another node from that state. Thus the clock uses
  the system time: the monotonic time of one node has no meaning on
  another node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.Schulte
  alias Octomocto.Schulte.{Classic, Layout, Store}

  @total 90
  # The game ends after this number. Dev config sets a small value for easier testing.
  @last Application.compile_env(:octomocto, :schulte_last_number, @total)
  @idle_timeout_ms :timer.minutes(5)
  # Test config turns the countdown off, so that the tests can pick at once.
  @countdown_ms Application.compile_env(:octomocto, :schulte_countdown_ms, 3000)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :schulte_rejoin_grace_ms,
                     :timer.seconds(30)
                   )

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

  def start_link({id, layout, mode, needed})
      when layout in [:random, :classic] and mode in [:easy, :normal] and needed in 1..4 do
    GenServer.start_link(__MODULE__, {id, layout, mode, needed}, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "schulte_game:" <> id

  @impl true
  def init({id, layout, mode, needed}) do
    schedule_idle_check()
    state = new_field(%{id: id, layout: layout, mode: mode, needed: needed, players: %{}})
    Store.write(state)
    {:ok, state}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init(%{} = state) do
    schedule_idle_check()

    if state.started_at != nil and now() < state.started_at do
      Process.send_after(self(), {:countdown_over, state.field_id}, state.started_at - now())
    end

    state = Enum.reduce(Map.keys(state.players), state, &leave(&2, &1))
    Store.write(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, pid, _user_id, _name, player_id}, _from, state)
      when is_map_key(state.players, player_id) do
    Process.monitor(pid)
    state = update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})
    Store.write(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  def handle_call({:join, _pid, _user_id, _name, _player_id}, _from, state)
      when map_size(state.players) >= state.needed do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, pid, user_id, name, _player_id}, _from, state) do
    Process.monitor(pid)
    # Unique in the cluster, because the game can move to another node
    player_id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {color_name, color} = pick_color(state.players)

    player = %{
      pid: pid,
      user_id: user_id,
      name: name,
      color: color,
      color_name: color_name,
      score: 0,
      joined_at: System.system_time(),
      # A reference while the player is away, see leave/2
      left: nil
    }

    state = put_in(state.players[player_id], player) |> start_clock()
    publish(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  @impl true
  def handle_cast({:pick, player_id, number}, %{next: number} = state)
      when is_map_key(state.players, player_id) and number <= @last do
    if started?(state) do
      state =
        state
        |> update_in([:players, player_id, :score], &(&1 + 1))
        |> Map.update!(:found_by, &Map.put(&1, number, player_id))
        |> Map.put(:next, number + 1)
        |> stop_clock()
        |> save_results()

      publish(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:pick, _player_id, _number}, state), do: {:noreply, state}

  # A restart is possible at any time. A field that is not finished is not
  # saved.
  def handle_cast(:restart, state) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0}} end)
    state = %{state | players: players} |> new_field() |> start_clock()
    publish(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, p} -> p.pid == pid end) do
      {player_id, _player} ->
        state = leave(state, player_id)
        Store.write(state)
        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  # The player did not join again in the grace time
  def handle_info({:remove, player_id, left}, state) do
    case state.players do
      %{^player_id => %{left: ^left}} ->
        state = %{state | players: Map.delete(state.players, player_id)}
        publish(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # The countdown is over: send the numbers. A countdown of an older field
  # does not count.
  def handle_info({:countdown_over, field_id}, %{field_id: field_id} = state) do
    broadcast(state)
    {:noreply, state}
  end

  def handle_info({:countdown_over, _field_id}, state), do: {:noreply, state}

  def handle_info(:idle_check, state) do
    if state.players == %{} do
      Store.delete(state.id)
      {:stop, :normal, state}
    else
      schedule_idle_check()
      {:noreply, state}
    end
  end

  defp new_field(state) do
    shapes = if state.layout == :classic, do: Classic.regions(), else: Layout.generate(@total)
    regions = Enum.zip_with(Enum.shuffle(1..@total), shapes, &Map.put(&2, :number, &1))

    Map.merge(state, %{
      # Groups the saved results of this field
      field_id: Ecto.UUID.generate(),
      regions: regions,
      next: 1,
      found_by: %{},
      # Nil until the game has all its players
      started_at: nil,
      finished_at: nil
    })
  end

  # The clock starts after the countdown, so `started_at` is in the future
  # until then.
  defp start_clock(%{started_at: nil} = state)
       when map_size(state.players) == state.needed do
    Process.send_after(self(), {:countdown_over, state.field_id}, @countdown_ms)
    %{state | started_at: now() + @countdown_ms}
  end

  defp start_clock(state), do: state

  defp stop_clock(state) when state.next > @last, do: %{state | finished_at: now()}
  defp stop_clock(state), do: state

  defp save_results(state)
       when state.next > @last and map_size(state.players) == state.needed do
    settings = %{
      "type" => Atom.to_string(state.layout),
      "mode" => Atom.to_string(state.mode),
      "players" => state.needed
    }

    players = Map.values(state.players)
    Schulte.save_results(state.field_id, settings, state.finished_at - state.started_at, players)
    state
  end

  defp save_results(state), do: state

  defp now, do: System.system_time(:millisecond)

  defp started?(state), do: state.started_at != nil and now() >= state.started_at

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

  # Removes the player after the grace time, unless the player joins again
  defp leave(state, player_id) do
    left = make_ref()
    Process.send_after(self(), {:remove, player_id, left}, @rejoin_grace_ms)
    update_in(state.players[player_id], &%{&1 | pid: nil, left: left})
  end

  defp publish(state) do
    Store.write(state)
    broadcast(state)
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
        %{id: id, name: p.name, color: p.color, color_name: p.color_name, score: p.score}
      end)

    # How narrow a number can get. The classic board has very narrow
    # shapes, where the printed puzzle squeezes the numbers a lot.
    {size, min_stretch} =
      if state.layout == :classic,
        do: {Classic.size(), 0.1},
        else: {Layout.size(), 0.3}

    waiting? = state.started_at == nil

    # Do not show the numbers before the start (also during the countdown),
    # so that nobody can look for them early.
    cells =
      if started?(state),
        do: Enum.map(state.regions, &Map.put(&1, :found_by, state.found_by[&1.number])),
        else: []

    %{
      board: Tuple.to_list(size),
      min_stretch: min_stretch,
      mode: state.mode,
      waiting: waiting?,
      # Below zero during the countdown
      elapsed_ms: if(waiting?, do: 0, else: (state.finished_at || now()) - state.started_at),
      total: @last,
      next: state.next,
      cells: cells,
      players: players,
      players_needed: state.needed
    }
  end
end
