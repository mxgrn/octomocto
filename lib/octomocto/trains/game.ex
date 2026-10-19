defmodule Octomocto.Trains.Game do
  @moduledoc """
  One cooperative trains game for a set number of players (`needed`), with
  the settings of `Octomocto.Trains.create_game/1`. All players play on one
  board, and each player owns some of its switches.

  The clients make the board and the trains from the `seed`, and each
  client runs the game. The server does not know the board. It keeps what
  the clients need to show the same game:

    * the start time of the round,
    * the position of each switch that a player flipped (the other
      switches keep their first position, which comes from the seed),
    * the route decisions: the owner of a switch decides which way each
      train goes at that switch (see `Octomocto.Trains.decide/5`).

  A client that joins in the middle of a round makes the full state from
  these.

  Players can join until the first round starts. Then a process that joins
  only watches. Each player has a slot (from 0 to `needed` - 1), and the
  clients give the switches to the players by their slots.

  A round starts after a countdown when the game has all its players.
  Restart starts a new round with a new board, also after a countdown. The clients tell when the round
  ends and how many trains got home (see `Octomocto.Trains.finish/4`).
  The first report of the round is the score of the round. When all
  players are still in the game, the game saves it as the result of each
  player (see `Octomocto.Trains.save_results/4`).

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A
  game for one player is only in the ongoing games. The game sends its new
  row after each change, and nil when its node stops. A process can also
  join only to watch (see `Octomocto.Trains.watch/1`).

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reload). Then the
  player is removed. The game stops after some time with no players.

  The game broadcasts on the `"trains_game:<id>"` PubSub topic:
  `{:trains_state, state}` after a change of the players or the round,
  and `{:trains_flip, flip}` and `{:trains_decision, decision}`.

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.Trains.Store` after each change. When its node stops, the
  game starts again on another node from that state. Thus the clock uses
  the system time: the monotonic time of one node has no meaning on
  another node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Lobby, Trains}
  alias Octomocto.Trains.Store

  @idle_timeout_ms :timer.minutes(5)
  # Test config turns the countdown off.
  @countdown_ms Application.compile_env(:octomocto, :trains_countdown_ms, 3000)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :trains_rejoin_grace_ms,
                     :timer.seconds(15)
                   )

  # The size of all boards, the same as `boardFor` in Trains.elm. The server
  # does not know the board, but it accepts only cells inside it, so that a
  # client cannot make the state grow without a limit.
  @cols 9
  @rows 7

  defguardp on_board(cell)
            when is_list(cell) and length(cell) == 2 and
                   hd(cell) in 0..(@cols - 1)//1 and hd(tl(cell)) in 0..(@rows - 1)//1

  # The number of trains of a round, the same as `trainCount` in Trains.elm
  defguardp trains(state) when state.trains_per_house * (state.switch_count + 1)

  @colors [
    {"pink", "#ec4899"},
    {"sky", "#0ea5e9"},
    {"lime", "#65a30d"},
    {"violet", "#8b5cf6"}
  ]

  def start_link(
        {id, %{players: _, switch_count: _, trains_per_house: _, pace: _, public: _}} = args
      ) do
    GenServer.start_link(__MODULE__, args, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "trains_game:" <> id

  def lobby_topic, do: "trains_lobby"

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. An ongoing game
  has the `:score` of the round (nil until the round ends) and its
  `:trains`.
  """
  def lobby_entry(%{public: true} = state) when map_size(state.players) > 0 do
    players =
      state.players
      |> Map.values()
      |> Enum.sort_by(& &1.slot)
      |> Enum.map(&Lobby.player/1)

    entry = %{
      id: state.id,
      settings: %{
        switch_count: state.switch_count,
        trains_per_house: state.trains_per_house,
        pace: state.pace
      },
      players_needed: state.needed,
      players: players
    }

    cond do
      state.listed ->
        Map.merge(entry, %{
          status: :open,
          seats_left: state.needed - map_size(state.players),
          created_at: state.created_at
        })

      state.started_at != nil ->
        Map.merge(entry, %{
          status: :ongoing,
          started_at: state.started_at,
          finished: state.score != nil,
          score: state.score,
          trains: trains(state)
        })

      # The round did not start yet
      true ->
        nil
    end
  end

  def lobby_entry(_state), do: nil

  @impl true
  def init({id, settings}) do
    # So that terminate/2 runs when the node stops
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    state =
      new_round(%{
        id: id,
        needed: settings.players,
        switch_count: settings.switch_count,
        trains_per_house: settings.trains_per_house,
        pace: settings.pace,
        players: %{},
        opened: true,
        public: settings.public,
        created_at: now(),
        # True while the game is in the list of open games. A game with one
        # player is never in it.
        listed: settings.public and settings.players > 1
      })

    store(state)
    {:ok, state}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init(%{} = state) do
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    # A state from before the results and the lists of the settings page
    state =
      Map.merge(
        %{round_id: Ecto.UUID.generate(), score: nil, public: false, listed: false},
        state
      )

    state = Enum.reduce(Map.keys(state.players), state, &leave(&2, &1))
    store(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, pid, _user_id, _name, player_id}, _from, state)
      when is_map_key(state.players, player_id) do
    Process.monitor(pid)
    state = update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})
    store(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  # The next game for all players, see `OctomoctoWeb.NextGame`
  def handle_call({:next_game, player_id, page}, _from, state) do
    {id, state} = Octomocto.GameProcess.next_game(state, player_id, page)
    {:reply, id, state}
  end

  def handle_call(:watch, _from, state) do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, _pid, _user_id, _name, _player_id}, _from, state)
      when map_size(state.players) >= state.needed or not state.opened do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, pid, user_id, name, _player_id}, _from, state) do
    Process.monitor(pid)
    # Unique in the cluster, because the game can move to another node
    player_id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    slot = Enum.find(0..(state.needed - 1), &(&1 not in slots(state)))
    {color_name, color} = Enum.at(@colors, slot)

    player = %{
      pid: pid,
      user_id: user_id,
      name: name,
      color: color,
      color_name: color_name,
      slot: slot,
      # A reference while the player is away, see leave/2
      left: nil
    }

    state = put_in(state.players[player_id], player)
    # The game leaves the open games when it is full for the first time
    state = %{state | listed: state.listed and map_size(state.players) < state.needed}
    state = start_round(state)
    publish(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  @impl true
  def handle_cast({:flip, player_id, cell, value}, state)
      when is_map_key(state.players, player_id) and on_board(cell) and value in [0, 1] do
    state = put_in(state.switches[cell], value)
    Store.write(state)
    broadcast(state, {:trains_flip, %{player_id: player_id, cell: cell, value: value}})
    {:noreply, state}
  end

  # The first decision counts. A second one can come when the switch gets
  # a new owner at the moment the train is there. The trains have the
  # numbers from 0 to the number of trains - 1 (see `trainCount` in
  # Trains.elm).
  def handle_cast({:decision, player_id, train, cell, exit}, state)
      when is_map_key(state.players, player_id) and state.started_at != nil and
             is_integer(train) and train >= 0 and
             train < trains(state) and
             on_board(cell) and on_board(exit) do
    if is_map_key(state.decisions, {train, cell}) do
      {:noreply, state}
    else
      state = put_in(state.decisions[{train, cell}], exit)
      Store.write(state)

      broadcast(
        state,
        {:trains_decision, %{player_id: player_id, train: train, cell: cell, exit: exit}}
      )

      {:noreply, state}
    end
  end

  def handle_cast({:finish, player_id, seed, correct}, state)
      when is_map_key(state.players, player_id) and seed == state.seed and
             state.started_at != nil and state.score == nil and is_integer(correct) and
             correct >= 0 and correct <= trains(state) do
    save_results(state, correct)
    state = %{state | score: correct}
    store(state)
    {:noreply, state}
  end

  def handle_cast({:restart, player_id}, state) when is_map_key(state.players, player_id) do
    state = state |> Map.delete(:next_game) |> new_round() |> start_round()
    publish(state)
    {:noreply, state}
  end

  def handle_cast(_request, state), do: {:noreply, state}

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, p} -> p.pid == pid end) do
      {player_id, _player} ->
        state = leave(state, player_id)
        store(state)
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

  # Sends the state again, so that the clients that missed the start time
  # (for example, after a reconnect) get it.
  def handle_info(:countdown_over, state) do
    broadcast(state, {:trains_state, public(state)})
    {:noreply, state}
  end

  def handle_info(:idle_check, state) do
    if state.players == %{} do
      Store.delete(state.id)
      {:stop, :normal, state}
    else
      schedule_idle_check()
      {:noreply, state}
    end
  end

  defp new_round(state) do
    Map.merge(state, %{
      # The clients make the board and the trains from it. Elm uses 32-bit
      # integers for seeds.
      seed: :rand.uniform(2_000_000_000),
      # The game id of the results of the round
      round_id: Ecto.UUID.generate(),
      # The number of trains that got home, nil until the round ends
      score: nil,
      # Nil until the game has all its players
      started_at: nil,
      # The positions of the flipped switches, by cell
      switches: %{},
      # The exits by {train, switch cell}
      decisions: %{}
    })
  end

  # The round starts after the countdown, when the game has all its players
  defp start_round(%{started_at: nil} = state) when map_size(state.players) == state.needed do
    Process.send_after(self(), :countdown_over, @countdown_ms)
    %{state | started_at: now() + @countdown_ms, opened: false}
  end

  defp start_round(state), do: state

  defp save_results(state, correct) when map_size(state.players) == state.needed do
    settings = %{
      "switch_count" => state.switch_count,
      "trains_per_house" => state.trains_per_house,
      "pace" => state.pace,
      "players" => state.needed
    }

    Trains.save_results(state.round_id, settings, correct, Map.values(state.players))
  end

  # A player left: the result does not count
  defp save_results(_state, _correct), do: nil

  defp slots(state), do: Enum.map(state.players, fn {_id, p} -> p.slot end)

  defp now, do: System.system_time(:millisecond)

  defp schedule_idle_check do
    Process.send_after(self(), :idle_check, @idle_timeout_ms)
  end

  # Removes the player after the grace time, unless the player joins again
  defp leave(state, player_id) do
    left = make_ref()
    Process.send_after(self(), {:remove, player_id, left}, @rejoin_grace_ms)
    update_in(state.players[player_id], &%{&1 | pid: nil, left: left})
  end

  # The node stops. The game leaves the lists of the settings page until a
  # player joins it again on another node (see `Octomocto.GameProcess`).
  @impl true
  def terminate(_reason, state) do
    if state.public, do: Lobby.broadcast(__MODULE__, state.id, nil)
  end

  # Writes the state to the store, and sends the new row of the game to the
  # settings pages
  defp store(state) do
    Store.write(state)
    if state.public, do: Lobby.broadcast(__MODULE__, state.id, lobby_entry(state))
  end

  defp publish(state) do
    store(state)
    broadcast(state, {:trains_state, public(state)})
  end

  defp broadcast(state, message) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), message)
  end

  # The state that clients see, ready to encode as JSON. Cells are [x, y]
  # lists.
  defp public(state) do
    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.slot end)
      |> Enum.map(fn {id, p} ->
        %{id: id, name: p.name, color: p.color, color_name: p.color_name, slot: p.slot}
      end)

    %{
      seed: state.seed,
      switch_count: state.switch_count,
      trains_per_house: state.trains_per_house,
      pace: state.pace,
      players: players,
      players_needed: state.needed,
      # Nil before the start. Below zero during the countdown.
      elapsed_ms: if(state.started_at, do: now() - state.started_at),
      switches: Enum.map(state.switches, fn {cell, value} -> %{cell: cell, value: value} end),
      decisions:
        Enum.map(state.decisions, fn {{train, cell}, exit} ->
          %{train: train, cell: cell, exit: exit}
        end)
    }
  end
end
