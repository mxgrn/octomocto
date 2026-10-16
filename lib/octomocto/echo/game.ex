defmodule Octomocto.Echo.Game do
  @moduledoc """
  One Echo game: a ring of colored pads and a sequence of pads that gets
  one pad longer in each round. The game owns the sequence and the players,
  and broadcasts each change on the `"echo_game:<id>"` PubSub topic as
  `{:echo_state, state}`.

  Alone, the player starts the game, and the game adds a random pad to the
  sequence. The browser plays the sequence back, and the player repeats it.
  When the player repeats all of it, the game adds one more random pad. A
  wrong pad ends the game.

  With 2 or 3 players, the game has no playback. In a turn, the player
  repeats the sequence and then adds a pad of their choice. Then the turn
  goes to the next player. The first player of a game only adds a pad. A
  player who taps a wrong pad is out. When only one player is still in,
  that player wins. A player who does nothing for some time loses the turn,
  but stays in. Nobody can tap a pad before the game has all its players.

  The score of a player is the length of the longest sequence that the
  player repeated. Each tap is in the state as the `last_tap`, so that the
  browsers of the other players light up its pad.

  As in `Octomocto.Memory.Game`, each player is bound to the process that
  joined, a player who leaves can join again for a short time, a public
  game is in the lists of the settings page (see `Octomocto.Lobby`), and
  the game writes its state to `Octomocto.Echo.Store` after each change.
  When the game ends with all its players, it saves the score of each
  player (see `Octomocto.Echo.save_results/3`).
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Echo, Lobby}
  alias Octomocto.Echo.Store

  @idle_timeout_ms :timer.minutes(5)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :echo_rejoin_grace_ms,
                     :timer.seconds(15)
                   )
  # With 2 or more players, the turn goes to the next player after this
  # time with no pad tapped
  @turn_timeout_ms :timer.seconds(15)

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

  def start_link({id, %{pads: pads, players: needed, public: public} = config})
      when pads in 2..8 and needed in 1..3 and is_boolean(public) do
    GenServer.start_link(__MODULE__, {id, config}, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "echo_game:" <> id

  def lobby_topic, do: "echo_lobby"

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. Each player has
  a `:score` and a `:turn`.
  """
  def lobby_entry(%{public: true} = state) when map_size(state.players) > 0 do
    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.joined_at end)
      |> Enum.map(fn {id, p} ->
        p |> Lobby.player() |> Map.merge(%{score: p.score, turn: id == state.turn})
      end)

    entry = %{
      id: state.id,
      settings: %{pads: state.pads},
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

      state.ready ->
        Map.merge(entry, %{
          status: :ongoing,
          started_at: state.ready_at,
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
      new_field(%{
        id: id,
        pads: config.pads,
        needed: config.players,
        players: %{},
        public: config.public,
        created_at: now(),
        # True while the game is in the list of open games. A game with one
        # player is never in it.
        listed: config.public and config.players > 1,
        # Counts the taps, so that a browser knows a new tap
        taps: 0
      })

    store(state)
    {:ok, state}
  end

  # The processes of the players were on the old node. The players can join
  # again during the grace time.
  def init(%{} = state) do
    Process.flag(:trap_exit, true)
    schedule_idle_check()

    state =
      Enum.reduce(Map.keys(state.players), state, &leave(&2, &1))
      |> restart_turn_timer()

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
      # The place in the order in which the players went out, or nil while
      # the player is in
      out: nil,
      joined_at: System.system_time(),
      # A reference while the player is away, see leave/2
      left: nil
    }

    state =
      put_in(state.players[player_id], player)
      |> Map.update!(:turn, &(&1 || player_id))
      |> make_ready()

    publish(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  @impl true
  def handle_cast({:start, player_id}, %{turn: player_id, sequence: []} = state)
      when state.needed == 1 and state.ready and state.finished_at == nil do
    state = add_random_pad(state)
    publish(state)
    {:noreply, state}
  end

  def handle_cast({:start, _player_id}, state), do: {:noreply, state}

  # Alone, the player can tap only after the start
  def handle_cast({:press, _player_id, _pad}, %{needed: 1, sequence: []} = state),
    do: {:noreply, state}

  def handle_cast({:press, player_id, pad}, %{turn: player_id} = state)
      when is_binary(player_id) and pad in 0..(state.pads - 1)//1 and state.ready and
             state.finished_at == nil do
    state =
      if state.step < length(state.sequence),
        do: repeat(state, pad),
        else: add_pad(state, pad)

    publish(state)
    {:noreply, state}
  end

  def handle_cast({:press, _player_id, _pad}, state), do: {:noreply, state}

  # A player can restart at any time. A game that is not finished is not
  # saved. Alone, the first round starts at once.
  def handle_cast({:restart, player_id}, state) when is_map_key(state.players, player_id) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0, out: nil}} end)

    state =
      %{state | players: players}
      |> new_field()
      |> Map.put(:turn, first_player(players))
      |> make_ready()

    state = if state.needed == 1, do: add_random_pad(state), else: state
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

  # The player did not join again in the grace time. When only one player
  # is still in, the game ends.
  def handle_info({:remove, player_id, left}, state) do
    case state.players do
      %{^player_id => %{left: ^left}} ->
        state =
          if state.turn == player_id,
            do: state |> pass_turn() |> restart_turn_timer(),
            else: state

        state = %{state | players: Map.delete(state.players, player_id)}
        state = if state.players == %{}, do: %{state | turn: nil}, else: state
        state = maybe_finish(state)
        publish(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  # The player of the turn did nothing for too long. A timer of an older
  # turn does not count.
  def handle_info({:turn_timeout, ref}, %{turn_ref: ref} = state) do
    state = state |> pass_turn() |> restart_turn_timer()
    publish(state)
    {:noreply, state}
  end

  def handle_info({:turn_timeout, _ref}, state), do: {:noreply, state}

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

  defp new_field(state) do
    Map.merge(state, %{
      # Groups the saved results of this game
      field_id: Ecto.UUID.generate(),
      # The pads, from 0
      sequence: [],
      # The number of pads of the sequence that the player of the turn
      # repeated. When it is the length of the sequence, the player adds a
      # pad (with 2 or more players).
      step: 0,
      # The id of the player whose turn it is
      turn: Map.get(state, :turn),
      # False until the game has all its players
      ready: false,
      # The time when the game had all its players
      ready_at: nil,
      finished_at: nil,
      # The id of the last player who is in, with 2 or more players
      winner: nil,
      # The last pad that a player tapped, see public/1
      last_tap: nil,
      # The time of the last tap, or of the start of the turn
      turn_since: nil,
      turn_ref: nil
    })
  end

  # A game that is ready once does not go back to the list of open games,
  # even when a player leaves later: nobody joins in the middle of a game.
  defp make_ready(%{ready: false} = state) when map_size(state.players) == state.needed do
    %{state | ready: true, ready_at: now(), listed: false} |> restart_turn_timer()
  end

  defp make_ready(state), do: state

  # The player of the turn taps the next pad of the sequence. After the last
  # pad, the player gets the length of the sequence as the score. Alone,
  # the game then adds a pad.
  defp repeat(state, pad) do
    if Enum.at(state.sequence, state.step) == pad do
      state = %{state | step: state.step + 1} |> tap(pad, true)
      length = length(state.sequence)

      cond do
        state.step < length ->
          restart_turn_timer(state)

        state.needed == 1 ->
          state |> put_score(length) |> add_random_pad()

        true ->
          state |> put_score(length) |> restart_turn_timer()
      end
    else
      state |> tap(pad, false) |> put_out() |> maybe_finish()
    end
  end

  # The player of the turn adds a pad, and the turn goes to the next player
  defp add_pad(state, pad) do
    %{state | sequence: state.sequence ++ [pad]}
    |> tap(pad, true)
    |> pass_turn()
    |> restart_turn_timer()
  end

  defp add_random_pad(state) do
    %{state | sequence: state.sequence ++ [Enum.random(0..(state.pads - 1))], step: 0}
  end

  defp tap(state, pad, ok) do
    taps = state.taps + 1
    %{state | taps: taps, last_tap: %{n: taps, pad: pad, player: state.turn, ok: ok}}
  end

  defp put_score(state, score) do
    update_in(state.players[state.turn].score, &max(&1, score))
  end

  # The player of the turn is out. Alone, the game ends. Else, the turn goes
  # to the next player who is in.
  defp put_out(state) do
    place = Enum.count(state.players, fn {_id, p} -> p.out != nil end) + 1
    state = put_in(state.players[state.turn].out, place)

    if state.needed == 1,
      do: state,
      else: state |> pass_turn() |> restart_turn_timer()
  end

  # The game ends when nobody (alone) or only one player (with 2 or more)
  # is still in
  defp maybe_finish(state) when state.ready and state.finished_at == nil do
    left = Enum.reject(state.players, fn {_id, p} -> p.out != nil end)

    if length(left) < min(state.needed, 2) do
      winner = if state.needed > 1, do: Enum.map(left, &elem(&1, 0)) |> List.first()
      turn = if state.needed > 1, do: winner, else: state.turn

      %{state | finished_at: now(), winner: winner, turn: turn}
      |> restart_turn_timer()
      |> save_results()
    else
      state
    end
  end

  defp maybe_finish(state), do: state

  # Gives the turn to the next player who is in. The player starts the
  # sequence again from its first pad.
  defp pass_turn(state) do
    %{state | step: 0, turn: next_player(state)}
  end

  # The players have their turns in the order in which they joined
  defp next_player(state) do
    order = player_order(state.players)
    {before, rest} = Enum.split_while(order, &(&1 != state.turn))

    # The players after the current one, then the ones before it, then the
    # current one
    (Enum.drop(rest, 1) ++ before ++ Enum.take(rest, 1))
    |> Enum.find(&(state.players[&1].out == nil))
  end

  defp first_player(players), do: players |> player_order() |> List.first()

  defp player_order(players) do
    players |> Enum.sort_by(fn {_id, p} -> p.joined_at end) |> Enum.map(&elem(&1, 0))
  end

  defp save_results(state) when map_size(state.players) == state.needed do
    settings = %{"pads" => state.pads, "players" => state.needed}
    Echo.save_results(state.field_id, settings, Map.values(state.players))
    state
  end

  defp save_results(state), do: state

  # The timer runs only in a game with 2 or more players
  defp restart_turn_timer(state) when state.ready and state.finished_at == nil do
    if state.needed > 1 do
      ref = make_ref()
      Process.send_after(self(), {:turn_timeout, ref}, @turn_timeout_ms)
      %{state | turn_since: now(), turn_ref: ref}
    else
      %{state | turn_since: now()}
    end
  end

  defp restart_turn_timer(state), do: %{state | turn_since: nil, turn_ref: nil}

  defp now, do: System.system_time(:millisecond)

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
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:echo_state, public(state)})
  end

  # The state that clients see, ready to encode as JSON. With 2 or more
  # players, the sequence is not in it: the players must remember it.
  # Alone, the browser plays it back.
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
          out: p.out,
          away: p.left != nil
        }
      end)

    %{
      pads: state.pads,
      sequence: if(state.needed == 1, do: state.sequence),
      length: length(state.sequence),
      step: state.step,
      waiting: not state.ready,
      finished: state.finished_at != nil,
      turn: state.turn,
      winner: state.winner,
      last_tap: state.last_tap,
      # The time since the last tap of the turn, and the time limit (nil
      # when there is none)
      turn_ms: if(state.turn_since, do: now() - state.turn_since, else: 0),
      turn_limit_ms: if(state.needed > 1, do: @turn_timeout_ms),
      players: players,
      players_needed: state.needed
    }
  end
end
