defmodule Octomocto.TurnServer do
  @moduledoc """
  The process of one multiplayer game where the players take turns. The
  game module gives the rules (see the callbacks), and this module does
  the rest, the same for all such games.

  The players, the rejoin and the lists of the settings page are the same
  as in all games, see `Octomocto.Seats`. The first player who joins has
  the turn. The game is `ready` when it has all its players, and nobody
  can move before that. A game that is ready once does not go back to the
  list of open games, even when a player leaves later: nobody joins in the
  middle of a game. A process can also join only to watch (see
  `Octomocto.GameProcess.watch/4`).

  With 2 or more players, the turn goes to the next player (see
  `c:pass_turn/1`) when the player of the turn does nothing for some time
  (`turn_timeout_ms`), or when that player is removed. The game module
  restarts the turn timer after each move with `restart_turn_timer/1`.

  A player can restart the game at any time: the scores go back to zero,
  a new field starts, and the first player has the turn. The game module
  saves the results itself, because each game saves other things.

  The game is registered in the whole cluster, and it writes its state to
  its store (see `Octomocto.GameStore`) after each change. When its node
  stops, the game starts again on another node from that state. The state
  is one flat map with the fields of this module and the fields of the
  game module, so that a state from older code can start again.

  A game module uses this module:

      defmodule Octomocto.Echo.Game do
        use Octomocto.TurnServer,
          # Each change is sent on the "echo_game:<id>" PubSub topic as
          # `{:echo_state, state}`
          topic: "echo_game",
          state_message: :echo_state,
          lobby_topic: "echo_lobby",
          store: Octomocto.Echo.Store
      end

  The game is created with `{id, config}`, where the config has the
  number of `:players` (1 to 4), `:public`, the settings of the game (see
  `c:init_settings/1`), and optionally `:turn_timeout_ms` and
  `:rejoin_grace_ms` (see `Octomocto.Seats`).
  """
  use GenServer

  alias Octomocto.{GameProcess, Lobby, Seats}

  @turn_timeout_ms :timer.seconds(15)

  @type state :: map()

  @doc """
  Gives the settings of the game from the config, as fields of the state.
  Fails for settings that are not valid.
  """
  @callback init_settings(config :: map()) :: map()

  @doc """
  Puts a new field into the state, at the start and at each restart. The
  state already has a new `:field_id`, `:ready` is false, and
  `:finished_at` is nil.
  """
  @callback new_field(state()) :: state()

  @doc """
  Does a move: a call or a cast to the game that this module does not
  handle itself, such as `{:press, player_id, pad}`. Gives the reply to a
  call (a cast ignores it) and the new state. With `:publish`, the game
  writes the state and sends it to all clients. With `:store`, the game
  only writes it. With `:ignore`, nothing changed.
  """
  @callback handle_move(move :: tuple(), state()) ::
              {:publish | :store | :ignore, reply :: term(), state()}

  @doc "Gives the turn to the next player."
  @callback pass_turn(state()) :: state()

  @doc "The fields of the state that clients see, added to the players and the turn."
  @callback public_field(state()) :: map()

  @doc "The settings of the game in its row in the lists, see `Octomocto.Lobby`."
  @callback lobby_settings(state()) :: map()

  @doc "The fields of the game of a player that clients see, added to the `:score`."
  @callback public_player(player :: map()) :: map()

  @doc "Adds the fields of the game to a new player."
  @callback new_player(player :: map()) :: map()

  @doc "Resets the fields of the game of a player when the game restarts."
  @callback reset_player(player :: map()) :: map()

  @doc "Changes the state after a player is removed, for example to end the game."
  @callback after_remove(state()) :: state()

  @doc "Changes the state after a restart, when the new field is ready."
  @callback after_restart(state()) :: state()

  @doc """
  Changes a state from older code when the game starts again from the
  store, for example to add a field with its default.
  """
  @callback restore(state()) :: state()

  @optional_callbacks public_player: 1,
                      new_player: 1,
                      reset_player: 1,
                      after_remove: 1,
                      after_restart: 1,
                      restore: 1

  defmacro __using__(opts) do
    quote do
      @behaviour Octomocto.TurnServer
      use Octomocto.GameProcess, server: Octomocto.TurnServer, options: unquote(opts)
    end
  end

  def start_link(game, {id, %{players: needed, public: public} = config})
      when needed in 1..4 and is_boolean(public) do
    state =
      game.init_settings(config)
      |> Map.merge(Seats.new(id, config))
      |> Map.merge(%{
        turn: nil,
        turn_timeout_ms: Map.get(config, :turn_timeout_ms, @turn_timeout_ms)
      })

    GenServer.start_link(__MODULE__, {game, {:new, state}}, name: game.via(id))
  end

  def start_link(game, %{id: id} = state) do
    GenServer.start_link(__MODULE__, {game, {:restore, state}}, name: game.via(id))
  end

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Seats.lobby_entry/4`). The game is ongoing from the time when
  it was ready. Each player has a `:score` and a `:turn`.
  """
  def lobby_entry(game, state) do
    started_at = if state.ready, do: state.ready_at

    Seats.lobby_entry(state, game.lobby_settings(state), started_at, fn id, p ->
      %{score: p.score, turn: id == state.turn}
    end)
  end

  defdelegate now, to: Seats

  @doc """
  Starts the time of a new turn. With 2 or more players, the turn goes to
  the next player when the time is over. Before the game is ready and
  after it is finished, there is no turn time.
  """
  def restart_turn_timer(state) when state.ready and state.finished_at == nil do
    if state.needed > 1 do
      ref = make_ref()
      Process.send_after(self(), {:turn_timeout, ref}, state.turn_timeout_ms)
      %{state | turn_since: now(), turn_ref: ref}
    else
      %{state | turn_since: now(), turn_ref: nil}
    end
  end

  def restart_turn_timer(state), do: %{state | turn_since: nil, turn_ref: nil}

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
      |> Map.put_new(:turn_timeout_ms, @turn_timeout_ms)

    state = if function_exported?(game, :restore, 1), do: game.restore(state), else: state
    state = state |> Seats.leave_all() |> restart_turn_timer()
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
    fields = optional(game, :new_player, %{score: 0})
    {player_id, state} = Seats.add(state, pid, user_id, name, guest_id, fields)
    state = state |> Map.update!(:turn, &(&1 || player_id)) |> make_ready()
    publish(game, state)
    {:reply, {:ok, player_id, public(game, state)}, {game, state}}
  end

  def handle_call(move, _from, {game, state}) do
    {reply, state} = move(game, move, state)
    {:reply, reply, {game, state}}
  end

  # A player can restart at any time. A game that is not finished is not
  # saved.
  @impl true
  def handle_cast({:restart, player_id}, {game, state})
      when is_map_key(state.players, player_id) do
    players =
      Map.new(state.players, fn {id, player} ->
        {id, optional(game, :reset_player, %{player | score: 0})}
      end)

    state =
      %{state | players: players}
      |> Map.delete(:next_game)
      |> then(&new_field(game, &1))
      |> then(&%{&1 | turn: List.first(Seats.order(&1))})
      |> make_ready()
      |> then(&optional(game, :after_restart, &1))

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

  # The player did not join again in the grace time. The player of the
  # turn gives the turn to the next player first.
  def handle_info({:remove, player_id, left}, {game, state}) do
    if Seats.remove?(state, player_id, left) do
      state =
        if state.turn == player_id,
          do: state |> game.pass_turn() |> restart_turn_timer(),
          else: state

      state = Seats.remove(state, player_id)
      state = if state.players == %{}, do: %{state | turn: nil}, else: state
      state = optional(game, :after_remove, state)
      publish(game, state)
      {:noreply, {game, state}}
    else
      {:noreply, {game, state}}
    end
  end

  # The player of the turn did nothing for too long. A timer of an older
  # turn does not count.
  def handle_info({:turn_timeout, ref}, {game, %{turn_ref: ref} = state}) do
    state = state |> game.pass_turn() |> restart_turn_timer()
    publish(game, state)
    {:noreply, {game, state}}
  end

  def handle_info({:turn_timeout, _ref}, game_state), do: {:noreply, game_state}

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
      {:publish, reply, state} ->
        publish(game, state)
        {reply, state}

      {:store, reply, state} ->
        store(game, state)
        {reply, state}

      {:ignore, reply, state} ->
        {reply, state}
    end
  end

  defp new_field(game, state) do
    state
    # Groups the saved results of this field
    |> Map.merge(%{
      field_id: Ecto.UUID.generate(),
      # False until the game has all its players
      ready: false,
      # The time when the game had all its players
      ready_at: nil,
      finished_at: nil,
      # The start of the turn, and the reference of its timer
      turn_since: nil,
      turn_ref: nil
    })
    |> game.new_field()
  end

  defp make_ready(%{ready: false} = state) when map_size(state.players) == state.needed do
    %{state | ready: true, ready_at: now(), listed: false} |> restart_turn_timer()
  end

  defp make_ready(state), do: state

  # Calls an optional callback of the game, or gives the value back
  defp optional(game, callback, value) do
    if function_exported?(game, callback, 1), do: apply(game, callback, [value]), else: value
  end

  defp store(game, state), do: Seats.write(state, game, game.__game__().store)

  defp publish(game, state) do
    store(game, state)
    message = {game.__game__().state_message, public(game, state)}
    Phoenix.PubSub.broadcast(Octomocto.PubSub, game.topic(state.id), message)
  end

  # The state that clients see, ready to encode as JSON
  defp public(game, state) do
    players =
      Seats.public_players(state, fn _id, p ->
        Map.put(public_player(game, p), :score, p.score)
      end)

    Map.merge(
      %{
        waiting: not state.ready,
        finished: state.finished_at != nil,
        turn: state.turn,
        # The time since the start of the turn, and the time limit (nil when
        # there is none)
        turn_ms: if(state.turn_since, do: now() - state.turn_since, else: 0),
        turn_limit_ms: if(state.needed > 1, do: state.turn_timeout_ms),
        players: players,
        players_needed: state.needed
      },
      game.public_field(state)
    )
  end

  defp public_player(game, player) do
    if function_exported?(game, :public_player, 1), do: game.public_player(player), else: %{}
  end
end
