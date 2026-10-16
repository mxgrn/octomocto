defmodule Octomocto.Mahjong.Game do
  @moduledoc """
  One multiplayer mahjong game. All players remove pairs of free tiles from
  the same Turtle board at the same time (see `Octomocto.Mahjong.Board`).
  The first player who removes a pair gets one point. The game ends when
  the board is empty. When no pair is free, any player can shuffle the
  tiles. The game owns the board and the players, and broadcasts each
  change on the `"mahjong:<id>"` PubSub topic as `{:mahjong_state, state}`.

  The game is for a set number of players (`needed`). The clock of each
  board starts when the game has all its players, after a countdown.
  Nobody sees the faces before that. A process that joins a full game only
  watches.

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. When a board ends with all players still in the
  game, the game saves the result of each player (see
  `Octomocto.Mahjong.save_results/4`). The game stops after some time with
  no players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A game for one player is only
  in the ongoing games. The game sends its new row after each change, and
  nil when its node stops. A process can also join only to watch (see
  `Octomocto.Mahjong.watch/1`).

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.Mahjong.Store` after each change. When its node stops, the
  game starts again on another node from that state. Thus the clock uses
  the system time: the monotonic time of one node has no meaning on
  another node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Lobby, Mahjong}
  alias Octomocto.Mahjong.{Board, Store}

  @idle_timeout_ms :timer.minutes(5)
  # Test config turns the countdown off, so that the tests can play at once.
  @countdown_ms Application.compile_env(:octomocto, :mahjong_countdown_ms, 3000)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :mahjong_rejoin_grace_ms,
                     :timer.seconds(15)
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

  def start_link({id, %{players: needed, public: public} = config})
      when needed in 1..4 and is_boolean(public) do
    GenServer.start_link(__MODULE__, {id, config}, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "mahjong:" <> id

  def lobby_topic, do: "mahjong_lobby"

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. Each player has
  a `:score`.
  """
  def lobby_entry(%{public: true} = state) when map_size(state.players) > 0 do
    players =
      state.players
      |> Map.values()
      |> Enum.sort_by(& &1.joined_at)
      |> Enum.map(&Map.put(Lobby.player(&1), :score, &1.score))

    entry = %{
      id: state.id,
      settings: %{},
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
          finished: state.finished_at != nil
        })

      # Not all players are back after a restart
      true ->
        nil
    end
  end

  def lobby_entry(_state), do: nil

  @impl true
  def init({id, config}) do
    # So that terminate/2 runs when the node stops
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    state =
      new_board(%{
        id: id,
        needed: config.players,
        players: %{},
        public: config.public,
        created_at: now(),
        # True while the game is in the list of open games. A game with one
        # player is never in it.
        listed: config.public and config.players > 1
      })

    store(state)
    {:ok, state}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init(%{} = state) do
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    if state.started_at != nil and now() < state.started_at do
      Process.send_after(self(), {:countdown_over, state.field_id}, state.started_at - now())
    end

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

  def handle_call(:watch, _from, state) do
    {:reply, {:ok, nil, public(state)}, state}
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

  # Two players can remove the same tile at the same time. The first one
  # gets the pair, and the second one is ignored.
  def handle_call({:remove, player_id, a, b}, _from, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil and a != b do
    if started?(state) and removable?(state.tiles, a, b) do
      state =
        state
        |> update_in([:players, player_id, :score], &(&1 + 1))
        |> Map.update!(:tiles, &Map.drop(&1, [a, b]))
        |> Map.put(:last, %{
          player_id: player_id,
          color: state.players[player_id].color,
          tiles: [public_tile({a, state.tiles[a]}), public_tile({b, state.tiles[b]})]
        })
        |> finish_when_empty()
        |> save_results()

      publish(state)
      {:reply, :ok, state}
    else
      {:reply, :ignored, state}
    end
  end

  def handle_call({:remove, _player_id, _a, _b}, _from, state) do
    {:reply, :ignored, state}
  end

  # Only when no pair is free, so that a late second click does nothing
  @impl true
  def handle_cast({:shuffle, player_id}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if started?(state) and not Board.free_pair?(state.tiles) do
      state = %{
        state
        | tiles: Board.shuffle(state.tiles),
          last: nil,
          shuffles: state.shuffles + 1
      }

      publish(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:shuffle, _player_id}, state), do: {:noreply, state}

  # A player can restart at any time. A board that is not cleared is not
  # saved.
  def handle_cast({:restart, player_id}, state) when is_map_key(state.players, player_id) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0}} end)
    state = %{state | players: players} |> new_board() |> start_clock()
    publish(state)
    {:noreply, state}
  end

  def handle_cast({:restart, _player_id}, state), do: {:noreply, state}

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

  # The countdown is over: send the faces. A countdown of an older board
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

  # The node stops. The game leaves the lists of the settings page until a
  # player joins it again on another node (see `Octomocto.GameProcess`).
  @impl true
  def terminate(_reason, state) do
    if in_lobby?(state), do: Lobby.broadcast(__MODULE__, state.id, nil)
  end

  defp new_board(state) do
    Map.merge(state, %{
      # Groups the saved results of this board
      field_id: Ecto.UUID.generate(),
      # The tiles on the board by id, each with its face and position
      tiles: Board.deal(),
      # The last pair that a player removed, with the player and its color
      last: nil,
      # Tells the shuffles apart, so that the pages can show each one
      shuffles: 0,
      # Nil until the game has all its players
      started_at: nil,
      finished_at: nil
    })
  end

  defp removable?(tiles, a, b) do
    with %{^a => tile_a, ^b => tile_b} <- tiles do
      positions = Board.positions(tiles)

      Board.pair?(tile_a.face, tile_b.face) and Board.free?(tile_a.pos, positions) and
        Board.free?(tile_b.pos, positions)
    else
      _ -> false
    end
  end

  defp finish_when_empty(state) do
    if state.tiles == %{}, do: %{state | finished_at: now()}, else: state
  end

  # The clock starts after the countdown, so `started_at` is in the future
  # until then. A game that starts once does not go back to the list of
  # open games, even when a player leaves later: nobody joins in the middle
  # of a race.
  defp start_clock(%{started_at: nil} = state)
       when map_size(state.players) == state.needed do
    Process.send_after(self(), {:countdown_over, state.field_id}, @countdown_ms)
    %{state | started_at: now() + @countdown_ms, listed: false}
  end

  defp start_clock(state), do: state

  defp save_results(state)
       when state.finished_at != nil and map_size(state.players) == state.needed do
    settings = %{"layout" => "turtle", "players" => state.needed}
    players = Map.values(state.players)

    Mahjong.save_results(
      state.field_id,
      settings,
      state.finished_at - state.started_at,
      players
    )

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

  # Writes the state to the store, and sends the new row of the game to the
  # settings pages
  defp store(state) do
    Store.write(state)
    if in_lobby?(state), do: Lobby.broadcast(__MODULE__, state.id, lobby_entry(state))
  end

  # True for a game that can be in the lists of the settings page
  defp in_lobby?(state), do: state.public

  defp publish(state) do
    store(state)
    broadcast(state)
  end

  defp broadcast(state) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:mahjong_state, public(state)})
  end

  # The state that clients see, ready to encode as JSON
  defp public(state) do
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

    started? = started?(state)
    tiles = Enum.map(state.tiles, &public_tile/1)

    %{
      # Do not show the faces before the start (also during the countdown),
      # so that nobody can look for pairs early.
      tiles: if(started?, do: tiles, else: Enum.map(tiles, &%{&1 | face: nil})),
      last: state.last,
      shuffles: state.shuffles,
      # True when no pair is free, so that the players can shuffle
      stuck: started? and state.tiles != %{} and not Board.free_pair?(state.tiles),
      waiting: waiting?,
      finished: state.finished_at != nil,
      # Below zero during the countdown
      elapsed_ms: if(waiting?, do: 0, else: (state.finished_at || now()) - state.started_at),
      players: players,
      players_needed: state.needed
    }
  end

  defp public_tile({id, %{face: face, pos: {layer, col, row}}}) do
    %{id: id, face: face, layer: layer, col: col, row: row}
  end
end
