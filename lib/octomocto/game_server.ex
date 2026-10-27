defmodule Octomocto.GameServer do
  @moduledoc """
  The process of one multiplayer game where all players race on the same
  field. The game module gives the rules (see the callbacks), and this
  module does the rest, the same for all such games.

  The game is for a set number of players (`needed`). The clock of each
  field starts when the game has all its players, after a countdown. A
  process that joins a full game only watches. A process can also join
  only to watch (see `Octomocto.GameProcess.watch/4`).

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. A player can restart the game at any time: the
  scores go back to zero and a new field starts. When a field is finished
  with all players still in the game, the game saves the result of each
  player with `save_results/4` of the game context. The game stops after
  some time with no players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A game for one player is only
  in the ongoing games. The game sends its new row after each change, and
  nil when its node stops.

  The game is registered in the whole cluster, and it writes its state to
  its store (see `Octomocto.GameStore`) after each change. When its node
  stops, the game starts again on another node from that state. Thus the
  clock uses the system time: the monotonic time of one node has no
  meaning on another node. The state is one flat map with the fields of
  this module and the fields of the game module, so that a state from
  older code can start again.

  A game module uses this module:

      defmodule Octomocto.Schulte.Game do
        use Octomocto.GameServer,
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

  alias Octomocto.{GameProcess, Lobby}

  @idle_timeout_ms :timer.minutes(5)
  @countdown_ms 3000
  @rejoin_grace_ms :timer.seconds(15)

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

  @optional_callbacks new_player: 1, reset_player: 1

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Octomocto.GameServer
      @game_server Map.new(opts)

      def child_spec(arg) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :temporary}
      end

      @doc "Starts a new game from `{id, config}`, or again from its state in the store."
      def start_link(arg), do: Octomocto.GameServer.start_link(__MODULE__, arg)

      def via(id), do: {:via, :global, {__MODULE__, id}}

      def topic(id), do: @game_server.topic <> ":" <> id

      def lobby_topic, do: @game_server.lobby_topic

      @doc "See `Octomocto.GameServer.lobby_entry/2`."
      def lobby_entry(state), do: Octomocto.GameServer.lobby_entry(__MODULE__, state)

      @doc false
      def __game_server__, do: @game_server
    end
  end

  def start_link(game, {id, %{players: needed, public: public} = config})
      when needed in 1..4 and is_boolean(public) do
    state =
      Map.merge(game.init_settings(config), %{
        id: id,
        needed: needed,
        players: %{},
        public: public,
        created_at: now(),
        # True while the game is in the list of open games. A game with one
        # player is never in it.
        listed: public and needed > 1,
        countdown_ms: Map.get(config, :countdown_ms, @countdown_ms),
        rejoin_grace_ms: Map.get(config, :rejoin_grace_ms, @rejoin_grace_ms)
      })

    GenServer.start_link(__MODULE__, {game, {:new, state}}, name: game.via(id))
  end

  def start_link(game, %{id: id} = state) do
    GenServer.start_link(__MODULE__, {game, {:restore, state}}, name: game.via(id))
  end

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. Each player has
  a `:score`.
  """
  # A state from before the lists has no `:public`
  def lobby_entry(game, %{public: true} = state) when map_size(state.players) > 0 do
    players =
      state.players
      |> Map.values()
      |> Enum.sort_by(& &1.joined_at)
      |> Enum.map(&Map.put(Lobby.player(&1), :score, &1.score))

    entry = %{
      id: state.id,
      settings: game.lobby_settings(state),
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
          finished: state.finished_at != nil
        })

      # Not all players are back after a restart
      true ->
        nil
    end
  end

  def lobby_entry(_game, _state), do: nil

  @doc "The system time in milliseconds, the same on all nodes."
  def now, do: System.system_time(:millisecond)

  @doc "True when the countdown of the field is over."
  def started?(state), do: state.started_at != nil and now() >= state.started_at

  @doc "Stops the clock of the field. The game saves the results after the move."
  def finish(state), do: %{state | finished_at: now()}

  @impl true
  def init({game, {:new, state}}) do
    # So that terminate/2 runs when the node stops
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    state = new_field(game, state)
    store(game, state)
    {:ok, {game, state}}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init({game, {:restore, state}}) do
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    state =
      state
      # A state from before the lists of the settings page
      |> Map.put_new(:public, false)
      |> Map.put_new(:created_at, now())
      |> Map.put_new(:listed, false)
      # A state from before the timings in the config
      |> Map.put_new(:countdown_ms, @countdown_ms)
      |> Map.put_new(:rejoin_grace_ms, @rejoin_grace_ms)

    if state.started_at != nil and now() < state.started_at do
      Process.send_after(self(), {:countdown_over, state.field_id}, state.started_at - now())
    end

    state = Enum.reduce(Map.keys(state.players), state, &leave(&2, &1))
    store(game, state)
    {:ok, {game, state}}
  end

  @impl true
  def handle_call({:join, pid, _user_id, _name, player_id, _guest_id}, _from, {game, state})
      when is_map_key(state.players, player_id) do
    Process.monitor(pid)
    state = update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})
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
    Process.monitor(pid)
    # Unique in the cluster, because the game can move to another node
    player_id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {color_name, color} = pick_color(state.players)

    player = %{
      pid: pid,
      user_id: user_id,
      guest_id: guest_id,
      name: name,
      color: color,
      color_name: color_name,
      score: 0,
      joined_at: System.system_time(),
      # A reference while the player is away, see leave/2
      left: nil
    }

    player =
      if function_exported?(game, :new_player, 1), do: game.new_player(player), else: player

    state = put_in(state.players[player_id], player) |> start_clock()
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
    case Enum.find(state.players, fn {_id, p} -> p.pid == pid end) do
      {player_id, _player} ->
        state = leave(state, player_id)
        store(game, state)
        {:noreply, {game, state}}

      nil ->
        {:noreply, {game, state}}
    end
  end

  # The player did not join again in the grace time
  def handle_info({:remove, player_id, left}, {game, state}) do
    case state.players do
      %{^player_id => %{left: ^left}} ->
        state = %{state | players: Map.delete(state.players, player_id)}
        publish(game, state)
        {:noreply, {game, state}}

      _ ->
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
      game.__game_server__().store.delete(state.id)
      {:stop, :normal, {game, state}}
    else
      schedule_idle_check()
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

    game.__game_server__().context.save_results(
      state.field_id,
      settings,
      finished_at - state.started_at,
      Map.values(state.players)
    )
  end

  defp save_results(_game, _old_state, _state), do: nil

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
    Process.send_after(self(), {:remove, player_id, left}, state.rejoin_grace_ms)
    update_in(state.players[player_id], &%{&1 | pid: nil, left: left})
  end

  # Writes the state to the store, and sends the new row of the game to the
  # settings pages
  defp store(game, state) do
    game.__game_server__().store.write(state)
    if state.public, do: Lobby.broadcast(game, state.id, lobby_entry(game, state))
  end

  defp publish(game, state) do
    store(game, state)
    broadcast(game, state)
  end

  defp broadcast(game, state) do
    message = {game.__game_server__().state_message, public(game, state)}
    Phoenix.PubSub.broadcast(Octomocto.PubSub, game.topic(state.id), message)
  end

  # The state that clients see, ready to encode as JSON
  defp public(game, state) do
    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.joined_at end)
      |> Enum.map(fn {id, p} ->
        %{
          id: id,
          name: p.name,
          color: p.color,
          color_name: p.color_name,
          score: p.score,
          away: p.left != nil
        }
      end)

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
