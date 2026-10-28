defmodule Octomocto.RaceServer do
  @moduledoc """
  The process of one multiplayer game where all players race on the same
  field. The game module gives the rules (see the callbacks), and this
  module does the rest, the same for all such games.

  The players, the rejoin and the lists of the settings page are the same
  as in all games, see `Octomocto.Seats`. The clock of each field starts
  when the game has all its players, after a countdown. A process can also
  join only to watch (see `Octomocto.GameProcess.watch/4`).

  A player can restart the game at any time: the scores go back to zero
  and a new field starts. When a field is finished with all players still
  in the game, the game saves the result of each player with
  `save_results/4` of the game context. The game sends its row in the lists
  after each change, and nil when its node stops.

  The game is registered in the whole cluster, and it writes its state to
  its store (see `Octomocto.GameStore`) after each change. When its node
  stops, the game starts again on another node from that state. Thus the
  clock uses the system time: the monotonic time of one node has no
  meaning on another node. The state is one flat map with the fields of
  this module and the fields of the game module, so that a state from
  older code can start again.

  A game module uses this module:

      defmodule Octomocto.Schulte.Game do
        use Octomocto.RaceServer,
          # Each change is sent on the "schulte_game:<id>" PubSub topic as
          # `{:schulte_state, state}`
          topic: "schulte_game",
          state_message: :schulte_state,
          lobby_topic: "schulte_lobby",
          store: Octomocto.Schulte.Store,
          # The module with `save_results/4`
          context: Octomocto.Schulte
      end

  The game is created with `{id, config}`, where the config has the
  number of `:players` (1 to 4), `:public`, the settings of the game (see
  `c:init_settings/1`), and optionally `:countdown_ms` and
  `:rejoin_grace_ms` (how long a player stays after its process stops).
  """
  use GenServer

  alias Octomocto.{GameProcess, Lobby, Seats}

  @countdown_ms 3000

  @type state :: map()

  @doc """
  Gives the settings of the game from the config, as fields of the state.
  Fails for settings that are not valid.
  """
  @callback init_settings(config :: map()) :: map()

  @doc """
  Puts a new field into the state, at the start and at each restart. The
  state already has a new `:field_id`, and `:started_at` and
  `:finished_at` are nil.
  """
  @callback new_field(state()) :: state()

  @doc """
  Does a move: a call or a cast to the game that this module does not
  handle itself, such as `{:pick, player_id, number}`. Gives the reply to
  a call (a cast ignores it) and the new state. With `:publish`, the game
  writes the state and sends it to all clients. With `:store`, the game
  only writes it, for a change that the clients do not see. With
  `:ignore`, nothing changed. A move that finishes the field calls
  `finish/1`.
  """
  @callback handle_move(move :: tuple(), state()) ::
              {:publish | :store | :ignore, reply :: term(), state()}

  @doc "The fields of the state that clients see, added to the players and the clock."
  @callback public_field(state()) :: map()

  @doc "The settings of the game in its row in the lists, see `Octomocto.Lobby`."
  @callback lobby_settings(state()) :: map()

  @doc """
  The settings of the saved results (see `save_results/4` of the game
  context), without the number of players, which this module adds.
  """
  @callback result_settings(state()) :: map()

  @doc "Adds the fields of the game to a new player."
  @callback new_player(player :: map()) :: map()

  @doc "Resets the fields of the game of a player when the game restarts."
  @callback reset_player(player :: map()) :: map()

  @doc """
  Changes a state from older code when the game starts again from the
  store, for example to add a field with its default.
  """
  @callback restore(state()) :: state()

  @optional_callbacks new_player: 1, reset_player: 1, restore: 1

  defmacro __using__(opts) do
    quote do
      @behaviour Octomocto.RaceServer
      use Octomocto.GameProcess, server: Octomocto.RaceServer, options: unquote(opts)
    end
  end

  def start_link(game, {id, %{players: needed, public: public} = config})
      when needed in 1..4 and is_boolean(public) do
    state =
      game.init_settings(config)
      |> Map.merge(Seats.new(id, config))
      |> Map.put(:countdown_ms, Map.get(config, :countdown_ms, @countdown_ms))

    GenServer.start_link(__MODULE__, {game, {:new, state}}, name: game.via(id))
  end

  def start_link(game, %{id: id} = state) do
    GenServer.start_link(__MODULE__, {game, {:restore, state}}, name: game.via(id))
  end

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Seats.lobby_entry/4`). Each player has a `:score`.
  """
  def lobby_entry(game, state) do
    Seats.lobby_entry(state, game.lobby_settings(state), state.started_at, fn _id, p ->
      %{score: p.score}
    end)
  end

  @doc "The system time in milliseconds, the same on all nodes."
  defdelegate now, to: Seats

  @doc "True when the countdown of the field is over."
  def started?(state), do: state.started_at != nil and now() >= state.started_at

  @doc "Stops the clock of the field. The game saves the results after the move."
  def finish(state), do: %{state | finished_at: now()}

  @impl true
  def init({game, {:new, state}}) do
    # So that terminate/2 runs when the node stops
    Process.flag(:trap_exit, true)
    Seats.schedule_idle_check()

    state = new_field(game, state)
    store(game, state)
    {:ok, {game, state}}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init({game, {:restore, state}}) do
    Process.flag(:trap_exit, true)
    Seats.schedule_idle_check()

    state =
      state
      |> Seats.restore()
      # A state from before the timings in the config
      |> Map.put_new(:countdown_ms, @countdown_ms)

    if state.started_at != nil and now() < state.started_at do
      Process.send_after(self(), {:countdown_over, state.field_id}, state.started_at - now())
    end

    state = if function_exported?(game, :restore, 1), do: game.restore(state), else: state
    state = Seats.leave_all(state)
    store(game, state)
    {:ok, {game, state}}
  end

  @impl true
  def handle_call({:join, pid, _user_id, _name, player_id, _guest_id}, _from, {game, state})
      when is_map_key(state.players, player_id) do
    state = Seats.rejoin(state, player_id, pid)
    store(game, state)
    {:reply, {:ok, player_id, public(game, state)}, {game, state}}
  end

  # The next game for all players, see `OctomoctoWeb.NextGame`
  def handle_call({:next_game, player_id, page}, _from, {game, state}) do
    {id, state} = GameProcess.next_game(state, player_id, page)
    {:reply, id, {game, state}}
  end

  def handle_call(:watch, _from, {game, state}) do
    {:reply, {:ok, nil, public(game, state)}, {game, state}}
  end

  def handle_call({:join, _pid, _user_id, _name, _player_id, _guest_id}, _from, {game, state})
      when map_size(state.players) >= state.needed do
    {:reply, {:ok, nil, public(game, state)}, {game, state}}
  end

  def handle_call({:join, pid, user_id, name, _player_id, guest_id}, _from, {game, state}) do
    fields = %{score: 0}

    fields =
      if function_exported?(game, :new_player, 1), do: game.new_player(fields), else: fields

    {player_id, state} = Seats.add(state, pid, user_id, name, guest_id, fields)
    state = start_clock(state)
    publish(game, state)
    {:reply, {:ok, player_id, public(game, state)}, {game, state}}
  end

  def handle_call(move, _from, {game, state}) do
    {reply, state} = move(game, move, state)
    {:reply, reply, {game, state}}
  end

  # A player can restart at any time. A field that is not finished is not
  # saved.
  @impl true
  def handle_cast({:restart, player_id}, {game, state})
      when is_map_key(state.players, player_id) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, reset_player(game, %{player | score: 0})}
      end)

    state =
      %{state | players: players}
      |> Map.delete(:next_game)
      |> then(&new_field(game, &1))
      |> start_clock()

    publish(game, state)
    {:noreply, {game, state}}
  end

  def handle_cast({:restart, _player_id}, game_state), do: {:noreply, game_state}

  def handle_cast(move, {game, state}) do
    {_reply, state} = move(game, move, state)
    {:noreply, {game, state}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, {game, state}) do
    if player_id = Seats.player_id(state, pid) do
      state = Seats.leave(state, player_id)
      store(game, state)
      {:noreply, {game, state}}
    else
      {:noreply, {game, state}}
    end
  end

  # The player did not join again in the grace time
  def handle_info({:remove, player_id, left}, {game, state}) do
    if Seats.remove?(state, player_id, left) do
      state = Seats.remove(state, player_id)
      publish(game, state)
      {:noreply, {game, state}}
    else
      {:noreply, {game, state}}
    end
  end

  # The countdown is over: send the field. A countdown of an older field
  # does not count.
  def handle_info({:countdown_over, field_id}, {game, %{field_id: field_id} = state}) do
    broadcast(game, state)
    {:noreply, {game, state}}
  end

  def handle_info({:countdown_over, _field_id}, game_state), do: {:noreply, game_state}

  def handle_info(:idle_check, {game, state}) do
    if state.players == %{} do
      game.__game__().store.delete(state.id)
      {:stop, :normal, {game, state}}
    else
      Seats.schedule_idle_check()
      {:noreply, {game, state}}
    end
  end

  # The node stops. The game leaves the lists of the settings page until a
  # player joins it again on another node (see `Octomocto.GameProcess`).
  @impl true
  def terminate(_reason, {game, state}) do
    if state.public, do: Lobby.broadcast(game, state.id, nil)
  end

  defp move(game, move, state) do
    case game.handle_move(move, state) do
      {:publish, reply, new_state} ->
        save_results(game, state, new_state)
        publish(game, new_state)
        {reply, new_state}

      {:store, reply, new_state} ->
        store(game, new_state)
        {reply, new_state}

      {:ignore, reply, new_state} ->
        {reply, new_state}
    end
  end

  defp new_field(game, state) do
    state
    # Groups the saved results of this field
    |> Map.merge(%{field_id: Ecto.UUID.generate(), started_at: nil, finished_at: nil})
    |> game.new_field()
  end

  defp reset_player(game, player) do
    if function_exported?(game, :reset_player, 1), do: game.reset_player(player), else: player
  end

  # The clock starts after the countdown, so `started_at` is in the future
  # until then. A game that starts once does not go back to the list of
  # open games, even when a player leaves later: nobody joins in the middle
  # of a race.
  defp start_clock(%{started_at: nil} = state)
       when map_size(state.players) == state.needed do
    Process.send_after(self(), {:countdown_over, state.field_id}, state.countdown_ms)
    %{state | started_at: now() + state.countdown_ms, listed: false}
  end

  defp start_clock(state), do: state

  # Saves the results when the move finished the field with all players
  # still in the game
  defp save_results(game, %{finished_at: nil}, %{finished_at: finished_at} = state)
       when finished_at != nil and map_size(state.players) == state.needed do
    settings = Map.put(game.result_settings(state), "players", state.needed)

    game.__game__().context.save_results(
      state.field_id,
      settings,
      finished_at - state.started_at,
      Map.values(state.players)
    )
  end

  defp save_results(_game, _old_state, _state), do: nil

  defp store(game, state), do: Seats.write(state, game, game.__game__().store)

  defp publish(game, state) do
    store(game, state)
    broadcast(game, state)
  end

  defp broadcast(game, state) do
    message = {game.__game__().state_message, public(game, state)}
    Phoenix.PubSub.broadcast(Octomocto.PubSub, game.topic(state.id), message)
  end

  # The state that clients see, ready to encode as JSON
  defp public(game, state) do
    players = Seats.public_players(state, fn _id, p -> %{score: p.score} end)
    waiting? = state.started_at == nil

    Map.merge(
      %{
        waiting: waiting?,
        finished: state.finished_at != nil,
        # Below zero during the countdown
        elapsed_ms: if(waiting?, do: 0, else: (state.finished_at || now()) - state.started_at),
        players: players,
        players_needed: state.needed
      },
      game.public_field(state)
    )
  end
end
