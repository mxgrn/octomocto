defmodule Octomocto.Overlap.Game do
  @moduledoc """
  One multiplayer Overlap game. The table has two cards: the top card of
  the pile and the next card from the deck (see `Octomocto.Overlap.Deck`).
  All players look for the symbol that the two cards have in common at the
  same time. The first player who taps it wins the card and gets one
  point. The card then goes on the pile, and the next card comes from the
  deck. The game ends when the deck is empty. The game owns the cards and
  the players, and broadcasts each change on the `"overlap:<id>"` PubSub
  topic as `{:overlap_state, state}`.

  A tap on another symbol blocks the taps of the player for a short time,
  so that a player cannot find the symbol by tapping all symbols fast.

  The game is for a set number of players (`needed`). The clock of each
  deck starts when the game has all its players, after a countdown. Nobody
  sees the cards before that. A process that joins a full game only
  watches.

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. When a deck ends with all players still in the
  game, the game saves the result of each player (see
  `Octomocto.Overlap.save_results/4`). The game stops after some time with
  no players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A game for one player is only
  in the ongoing games. The game sends its new row after each change, and
  nil when its node stops. A process can also join only to watch (see
  `Octomocto.Overlap.watch/1`).

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.Overlap.Store` after each change. When its node stops, the
  game starts again on another node from that state. Thus the clock uses
  the system time: the monotonic time of one node has no meaning on
  another node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Lobby, Overlap}
  alias Octomocto.Overlap.{Deck, Store}

  @idle_timeout_ms :timer.minutes(5)
  # Test config turns the countdown off, so that the tests can play at once.
  @countdown_ms Application.compile_env(:octomocto, :overlap_countdown_ms, 3000)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :overlap_rejoin_grace_ms,
                     :timer.seconds(15)
                   )
  # How long the taps of a player are blocked after a wrong symbol. The page
  # blocks them for 1 second. The block here is a bit shorter, so that the
  # first tap after the block on the page is not lost on the way.
  @freeze_ms 800

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

  def topic(id), do: "overlap:" <> id

  def lobby_topic, do: "overlap_lobby"

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
      new_deck(%{
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
      # The system time in ms until which the taps of the player are blocked
      frozen_until: 0,
      joined_at: System.system_time(),
      # A reference while the player is away, see leave/2
      left: nil
    }

    state = put_in(state.players[player_id], player) |> start_clock()
    publish(state)
    {:reply, {:ok, player_id, public(state)}, state}
  end

  # Two players can tap the common symbol at the same time. The first tap
  # wins the card. The second tap is for cards that are not on the table
  # any more, so it is ignored and does not block the player.
  @impl true
  def handle_cast({:tap, player_id, pile, card, symbol}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    cond do
      not started?(state) or state.pile.id != pile or state.card.id != card or
          now() < state.players[player_id].frozen_until ->
        {:noreply, state}

      symbol == Deck.common(state.pile, state.card) ->
        state =
          state
          |> update_in([:players, player_id, :score], &(&1 + 1))
          |> Map.put(:last, %{
            player_id: player_id,
            color: state.players[player_id].color,
            symbol: symbol
          })
          |> next_card()
          |> save_results()

        publish(state)
        {:noreply, state}

      true ->
        state = put_in(state.players[player_id].frozen_until, now() + @freeze_ms)
        store(state)
        {:noreply, state}
    end
  end

  def handle_cast({:tap, _player_id, _pile, _card, _symbol}, state), do: {:noreply, state}

  # A player can restart at any time. A deck that is not finished is not
  # saved.
  def handle_cast({:restart, player_id}, state) when is_map_key(state.players, player_id) do
    players = Map.new(state.players, fn {id, p} -> {id, %{p | score: 0, frozen_until: 0}} end)
    state = %{state | players: players} |> new_deck() |> start_clock()
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

  # The countdown is over: send the cards. A countdown of an older deck
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

  defp new_deck(state) do
    [pile, card | deck] = Deck.shuffled()

    Map.merge(state, %{
      # Groups the saved results of this deck
      field_id: Ecto.UUID.generate(),
      # The top card of the pile, and the card that the players try to win
      pile: pile,
      card: card,
      deck: deck,
      # The last symbol that a player found, with the player and its color
      last: nil,
      # Nil until the game has all its players
      started_at: nil,
      finished_at: nil
    })
  end

  # The won card goes on the pile. With no cards left in the deck, the game
  # ends, and the won card stays on the table with the old pile card.
  defp next_card(%{deck: []} = state), do: %{state | finished_at: now()}

  defp next_card(%{deck: [next | deck]} = state) do
    %{state | pile: state.card, card: next, deck: deck}
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
    settings = %{"symbols" => 8, "players" => state.needed}
    players = Map.values(state.players)

    Overlap.save_results(
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
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:overlap_state, public(state)})
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

    %{
      # Do not show the cards before the start (also during the countdown),
      # so that nobody can look for the symbol early.
      pile: if(started?, do: state.pile),
      card: if(started?, do: state.card),
      # The cards that the players can still win: the deck, and the card on
      # the table
      cards_left: if(state.finished_at, do: 0, else: length(state.deck) + 1),
      last: state.last,
      waiting: waiting?,
      finished: state.finished_at != nil,
      # Below zero during the countdown
      elapsed_ms: if(waiting?, do: 0, else: (state.finished_at || now()) - state.started_at),
      players: players,
      players_needed: state.needed
    }
  end
end
