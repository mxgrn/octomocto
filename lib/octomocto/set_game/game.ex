defmodule Octomocto.SetGame.Game do
  @moduledoc """
  One multiplayer Set game. The table has 12 cards from a deck of 81, or
  of 27 solid cards in the easy mode (see `Octomocto.SetGame.Deck`). All players look for sets at the same time,
  and the first player who claims a set gets one point. The cards of the
  set go off the table, and cards from the deck take their places. A wrong
  claim changes nothing.

  When the table has no set, 3 more cards come from the deck until it has
  one. The next set then only goes off the table, and the last cards move
  into its places, so that the table goes back to 12 cards. The game ends
  when the deck is empty and the table has no set. The game owns the table
  and the players, and broadcasts each change on the `"set_game:<id>"`
  PubSub topic as `{:set_state, state}`.

  The game is for a set number of players (`needed`). The clock of each
  table starts when the game has all its players, after a countdown.
  Nobody sees the cards before that. A process that joins a full game only
  watches.

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. When a table ends with all players still in the
  game, the game saves the result of each player (see
  `Octomocto.SetGame.save_results/4`). The game stops after some time with
  no players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A game for one player is only
  in the ongoing games. The game sends
  its new row after each change, and nil when its node stops. A process
  can also join only to watch (see `Octomocto.SetGame.watch/1`).

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.SetGame.Store` after each change. When its node stops, the
  game starts again on another node from that state. Thus the clock uses
  the system time: the monotonic time of one node has no meaning on
  another node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Lobby, SetGame}
  alias Octomocto.SetGame.{Deck, Store}

  @idle_timeout_ms :timer.minutes(5)
  # Test config turns the countdown off, so that the tests can claim at once.
  @countdown_ms Application.compile_env(:octomocto, :set_countdown_ms, 3000)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :set_rejoin_grace_ms,
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

  def start_link({id, %{players: needed, public: public, mode: mode} = config})
      when needed in 1..5 and is_boolean(public) and mode in ~w(easy normal) do
    GenServer.start_link(__MODULE__, {id, config}, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "set_game:" <> id

  def lobby_topic, do: "set_lobby"

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
      # The store can have a state from before the modes
      settings: %{mode: Map.get(state, :mode, "normal")},
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
      new_table(%{
        id: id,
        needed: config.players,
        mode: config.mode,
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
    # A state from before the modes
    state = Map.put_new(state, :mode, "normal")
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

  # Two players can claim the same cards at the same time. The first claim
  # takes the cards, and the second one is not a set on the table any more.
  @impl true
  def handle_cast({:claim, player_id, cards}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if started?(state) and Enum.all?(cards, &(&1 in state.table)) and Deck.set?(cards) do
      state =
        state
        |> update_in([:players, player_id, :score], &(&1 + 1))
        |> Map.put(:last_set, %{player_id: player_id, cards: cards})
        |> take_set(cards)
        |> deal_until_set()
        |> save_results()

      publish(state)
      {:noreply, state}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:claim, _player_id, _cards}, state), do: {:noreply, state}

  # A player can restart at any time. A table that is not finished is not
  # saved.
  def handle_cast({:restart, player_id}, state) when is_map_key(state.players, player_id) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0}} end)
    state = %{state | players: players} |> new_table() |> start_clock()
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

  # The countdown is over: send the cards. A countdown of an older table
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

  defp new_table(state) do
    {table, deck} = Enum.split(Deck.shuffled(state.mode), Deck.table())

    Map.merge(state, %{
      # Groups the saved results of this table
      field_id: Ecto.UUID.generate(),
      table: table,
      deck: deck,
      # The last set that a player found
      last_set: nil,
      # Nil until the game has all its players
      started_at: nil,
      finished_at: nil
    })
    |> deal_until_set()
  end

  # With no extra cards on the table, new cards from the deck take the
  # places of the set. Else the last cards of the table move into the
  # places of the set, so that the other cards stay where they are.
  defp take_set(state, cards) do
    if length(state.table) > Deck.table() or state.deck == [] do
      {head, tail} = Enum.split(state.table, length(state.table) - 3)
      %{state | table: fill(head, cards, tail -- cards)}
    else
      {new, deck} = Enum.split(state.deck, 3)
      %{state | table: fill(state.table, cards, new), deck: deck}
    end
  end

  # Puts the new cards into the places of the set cards, in order
  defp fill(table, set, new) do
    {table, []} =
      Enum.map_reduce(table, new, fn card, new ->
        if card in set, do: {hd(new), tl(new)}, else: {card, new}
      end)

    table
  end

  # Adds 3 cards while the table has no set. With no cards left in the
  # deck, the game ends.
  defp deal_until_set(state) do
    cond do
      Deck.any_set?(state.table) ->
        state

      state.deck == [] ->
        %{state | finished_at: now()}

      true ->
        {new, deck} = Enum.split(state.deck, 3)
        deal_until_set(%{state | table: state.table ++ new, deck: deck})
    end
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
    settings = %{"mode" => state.mode, "players" => state.needed}
    players = Map.values(state.players)

    SetGame.save_results(
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
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:set_state, public(state)})
  end

  # The state that clients see, ready to encode as JSON.
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

    %{
      # Do not show the cards before the start (also during the countdown),
      # so that nobody can look for sets early.
      table: if(started?(state), do: state.table, else: []),
      deck_left: length(state.deck),
      last_set: state.last_set,
      waiting: waiting?,
      finished: state.finished_at != nil,
      # Below zero during the countdown
      elapsed_ms: if(waiting?, do: 0, else: (state.finished_at || now()) - state.started_at),
      players: players,
      players_needed: state.needed
    }
  end
end
