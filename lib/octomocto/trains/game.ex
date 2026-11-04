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
      train goes at that switch (see `Octomocto.Trains.decide/5`). Each
      decision keeps the player who made it, so that the clients can count
      the errors of each player.

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

  A game of the campaign (see `Octomocto.Trains.Campaign`) has one player:
  the signed-in user who started it. Other processes only watch, for
  example from the ongoing games of the settings page. The game saves each
  finished round as a run of the level (see
  `Octomocto.Trains.Campaign.save_run/3`) and as a result with the level in
  its settings. Restart starts a new round of the same level.

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

  alias Octomocto.{GameEnd, Lobby, Seats, Trains}
  alias Octomocto.Trains.{Campaign, Store}

  # Test config turns the countdown off.
  @countdown_ms Application.compile_env(:octomocto, :trains_countdown_ms, 3000)
  # How long a player stays after its process stops, when the config of
  # the game does not say (see `Octomocto.Seats`)
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

  # The color of each slot
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
      settings: lobby_settings(state),
      players_needed: state.needed,
      players: players,
      created_at: state.created_at
    }

    cond do
      state.listed ->
        Map.merge(entry, %{
          status: :open,
          seats_left: state.needed - map_size(state.players)
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

  @doc """
  The settings of the game in its row of the lists, and in the bar of the
  game page (see `OctomoctoWeb.GameBarLive`).
  """
  def lobby_settings(state) do
    settings = %{
      switch_count: state.switch_count,
      trains_per_house: state.trains_per_house,
      pace: state.pace
    }

    # A game of the campaign has its level. Thus it never has the settings
    # of a new game of the settings page.
    if state.campaign, do: Map.put(settings, :campaign, state.campaign.level), else: settings
  end

  @impl true
  def init({id, settings}) do
    # So that terminate/2 runs when the node stops
    Process.flag(:trap_exit, true)
    Seats.schedule_idle_check()

    state =
      %{
        switch_count: settings.switch_count,
        trains_per_house: settings.trains_per_house,
        pace: settings.pace,
        opened: true,
        # The `:level` and the `:user_id` of the player of a game of the
        # campaign, else nil
        campaign: Map.get(settings, :campaign)
      }
      |> Map.merge(Seats.new(id, Map.put_new(settings, :rejoin_grace_ms, @rejoin_grace_ms)))
      |> new_round()

    store(state)
    {:ok, state}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init(%{} = state) do
    Process.flag(:trap_exit, true)
    Seats.schedule_idle_check()

    # A state from before the results
    state =
      Map.merge(%{round_id: Ecto.UUID.generate(), score: nil}, state)
      # A state from before the campaign
      |> Map.put_new(:campaign, nil)
      # A state from before the timings in the config
      |> Map.put_new(:rejoin_grace_ms, @rejoin_grace_ms)
      |> with_deciders()
      |> Seats.restore()
      |> Seats.leave_all()

    store(state)
    {:ok, state}
  end

  @impl true
  # A join from a node with older code, or from a player who did not come
  # from a list of open games (see `Octomocto.GameProcess.join/9`)
  def handle_call({:join, pid, user_id, name, player_id, guest_id}, from, state),
    do: handle_call({:join, pid, user_id, name, player_id, guest_id, false}, from, state)

  def handle_call({:join, pid, _user_id, _name, player_id, _guest_id, _from_lobby}, _from, state)
      when is_map_key(state.players, player_id) do
    state = Seats.rejoin(state, player_id, pid)
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

  def handle_call(
        {:join, _pid, _user_id, _name, _player_id, _guest_id, _from_lobby},
        _from,
        state
      )
      when map_size(state.players) >= state.needed or not state.opened do
    {:reply, {:ok, nil, public(state)}, state}
  end

  # Only the user who started a game of the campaign can play it
  def handle_call(
        {:join, _pid, user_id, _name, _player_id, _guest_id, _from_lobby},
        _from,
        %{campaign: %{} = campaign} = state
      )
      when user_id != campaign.user_id do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, pid, user_id, name, _player_id, guest_id, from_lobby}, _from, state) do
    slot = Enum.find(0..(state.needed - 1), &(&1 not in slots(state)))
    {color_name, color} = Enum.at(@colors, slot)
    fields = %{slot: slot, color: color, color_name: color_name}
    {player_id, state} = Seats.add(state, pid, user_id, name, guest_id, from_lobby, fields)
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
      state = put_in(state.decisions[{train, cell}], {exit, player_id})
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
    state = save_results(state, correct)
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
    if player_id = Seats.player_id(state, pid) do
      state = Seats.leave(state, player_id)
      store(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  # The player did not join again in the grace time
  def handle_info({:remove, player_id, left}, state) do
    if Seats.remove?(state, player_id, left) do
      state = Seats.remove(state, player_id)
      publish(state)
      {:noreply, state}
    else
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
      Seats.schedule_idle_check()
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
      # The {exit, player id} by {train, switch cell}
      decisions: %{}
    })
  end

  # The round starts after the countdown, when the game has all its players
  defp start_round(%{started_at: nil} = state) when map_size(state.players) == state.needed do
    Process.send_after(self(), :countdown_over, @countdown_ms)
    %{state | started_at: now() + @countdown_ms, opened: false}
  end

  defp start_round(state), do: state

  # A round of the campaign is a run of the level, and also a result. The
  # level in the settings keeps it out of the lists of the settings page,
  # which look for the exact settings.
  defp save_results(%{campaign: %{} = campaign} = state, correct) do
    Campaign.save_run(campaign.user_id, campaign.level, correct)

    settings = %{
      "switch_count" => state.switch_count,
      "trains_per_house" => state.trains_per_house,
      "pace" => state.pace,
      "players" => state.needed,
      "campaign" => campaign.level
    }

    Trains.save_results(state.round_id, settings, correct, Map.values(state.players))
    state
  end

  defp save_results(state, correct) when map_size(state.players) == state.needed do
    settings = %{
      "switch_count" => state.switch_count,
      "trains_per_house" => state.trains_per_house,
      "pace" => state.pace,
      "players" => state.needed
    }

    Trains.save_results(state.round_id, settings, correct, Map.values(state.players))
    GameEnd.finished(state)
  end

  # A player left: the result does not count
  defp save_results(state, _correct), do: state

  # A state from before the deciders has only the exits. These decisions
  # have no player.
  defp with_deciders(state) do
    decisions =
      Map.new(state.decisions, fn
        {key, {_exit, _player_id} = decision} -> {key, decision}
        {key, exit} -> {key, {exit, nil}}
      end)

    %{state | decisions: decisions}
  end

  defp slots(state), do: Enum.map(state.players, fn {_id, p} -> p.slot end)

  defp now, do: Seats.now()

  # The node stops. The game leaves the lists of the settings page until a
  # player joins it again on another node (see `Octomocto.GameProcess`).
  @impl true
  def terminate(_reason, state) do
    if state.public, do: Lobby.broadcast(__MODULE__, state.id, nil)
  end

  # Writes the state to the store, and sends the new row of the game to the
  # settings pages
  defp store(state), do: Seats.write(state, __MODULE__, Store)

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
        Enum.map(state.decisions, fn {{train, cell}, {exit, player_id}} ->
          %{train: train, cell: cell, exit: exit, player_id: player_id}
        end),
      # The level of a game of the campaign, the number of levels and the
      # trains that must get home to pass the level
      campaign:
        if(state.campaign,
          do: %{
            level: state.campaign.level,
            levels: Campaign.count(),
            pass: Campaign.pass_count(trains(state))
          }
        )
    }
  end
end
