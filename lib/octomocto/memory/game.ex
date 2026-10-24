defmodule Octomocto.Memory.Game do
  @moduledoc """
  One multiplayer Memory game: a field of face-down cards, with sets of 2
  (pairs) or 3 (triplets) cards that have the same image. The players turn
  the cards face up in turns. When the cards of a turn make a set, they go
  off the field, the player gets one point for each card, and the player
  turns more cards. When they do not make a set, they stay face up until
  the next player turns a card, and the turn goes to the next player. The
  game owns the field and the players, and broadcasts each change on the
  `"memory_game:<id>"` PubSub topic as `{:memory_state, state}`.

  The game is for a set number of players (`needed`). Nobody can turn a
  card before the game has all its players. The clock starts with the first
  card. With more than 2 players, a player who does nothing for some time
  loses the turn.

  Each player is bound to the process that joined (a channel). When that
  process stops, the player stays in the game for a short time, so that
  the same player can join again (for example, after a reconnect). Then
  the player is removed. When all cards are off the field with all players
  still in the game, the game saves the result of each player (see
  `Octomocto.Memory.save_results/4`). The game stops after some time with no
  players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time, then in the ongoing games. A game for one player is only
  in the ongoing games. The game sends
  its new row after each change, and nil when its node stops.

  Each player has an accuracy (see `Octomocto.Memory.accuracy/1`): the
  game counts the `correct` and the `errors` flips of the player. Only the
  flips where the player can know the answer are counted (see
  `check_flip/3`). All players see all cards, so the cards that were seen
  (`seen`) are the same for all players.

  A process can also join only to watch (see `Octomocto.Memory.watch/1`).

  A game of the campaign (see `Octomocto.Memory.Campaign`) has one player:
  the signed-in user who started it. Other processes only watch, for
  example from the ongoing games of the settings page. The
  field stops at the first error of the player (`failed`), and the game
  saves the run of the level (see `Octomocto.Memory.Campaign.save_run/3`)
  and a result with the level in its settings.

  The players of a game with 2 or more players play a match: each finished
  field gives a win to its winner (`wins` of the player), or a tie
  (`ties`). Between two fields, one player can change the settings of the
  game on the settings page (see `Octomocto.Memory.edit_settings/3`). The
  player is in `editing` while the page is open, and the other players
  cannot start a field until the player is back.

  A field can have bombs (`bombs`): single cards that take the places of 1
  to 3 sets. A bomb is never part of a set. The first player who turns a
  bomb is safe, and the bomb counts as one card of the turn. A player who
  turns a bomb that was seen is out (`dead`): the player keeps the score,
  but has no more turns. The last player who is not out plays alone. The
  field ends when all sets are off the field or all players are out. When
  the only player of a game is out, the field ends (`failed`), and the game
  does not save it.

  When a player turns the last bomb that was not seen as the first card of
  a try, the player can demine the field (`offer`): the next card decides.
  A bomb starts the demining, and another card continues the try as usual.
  When all bombs were
  seen, a player who turns a bomb as the first card of a try must demine
  the field. During the demining (`demining`), the player turns all other
  bombs. A card that is not a bomb puts the player out. When all bombs are
  face up, they go off the field as a set: the player gets the points of a
  set, is a `deminer`, and turns again.

  The game is registered in the whole cluster, and it writes its state to
  `Octomocto.Memory.Store` after each change. When its node stops, the game
  starts again on another node from that state. Thus the clock uses the
  system time: the monotonic time of one node has no meaning on another
  node.
  """
  use GenServer, restart: :temporary

  alias Octomocto.{Lobby, Memory}
  alias Octomocto.Memory.{Board, Campaign, Store, Themes}

  @idle_timeout_ms :timer.minutes(5)
  # How long a player stays after its process stops
  @rejoin_grace_ms Application.compile_env(
                     :octomocto,
                     :memory_rejoin_grace_ms,
                     :timer.seconds(15)
                   )
  # With 2 or more players, the turn goes to the next player after this
  # time with no card turned
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

  def start_link(
        {id, %{theme: theme, set: set, cards: cards, players: needed, public: public} = config}
      )
      when set in [2, 3] and needed in 1..4 and is_boolean(public) do
    true = valid_size?(config, theme, set, cards)
    true = Map.get(config, :bombs, 0) in Board.bomb_counts(set, cards)
    GenServer.start_link(__MODULE__, {id, config}, name: via(id))
  end

  # Starts the game again from its state in the store
  def start_link(%{id: id} = state) do
    GenServer.start_link(__MODULE__, state, name: via(id))
  end

  # A level of the campaign has its own size, which can be smaller than
  # the sizes of the settings page
  defp valid_size?(%{campaign: %{level: level}}, _theme, set, cards),
    do: match?(%{set: ^set, cards: ^cards}, Campaign.get(level))

  defp valid_size?(_config, theme, set, cards), do: cards in Board.sizes(theme, set)

  def via(id), do: {:via, :global, {__MODULE__, id}}

  def topic(id), do: "memory_game:" <> id

  def lobby_topic, do: "memory_lobby"

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. Each player has
  a `:score` and a `:turn`.
  """
  # A state from before the lists has no `:public`
  def lobby_entry(%{public: true} = state) when map_size(state.players) > 0 do
    players =
      state.players
      |> Enum.sort_by(fn {_id, p} -> p.joined_at end)
      |> Enum.map(fn {id, p} ->
        p |> Lobby.player() |> Map.merge(%{score: p.score, turn: id == state.turn})
      end)

    settings = %{
      theme: state.theme,
      set: state.set,
      cards: state.size,
      # A stored state from before the bombs has no `:bombs`
      bombs: Map.get(state, :bombs, 0)
    }

    entry = %{
      id: state.id,
      # A game of the campaign has its level. Thus it never has the
      # settings of a new game of the settings page.
      settings:
        if(state.campaign, do: Map.put(settings, :campaign, state.campaign.level), else: settings),
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
        # With the theme "random", each new field gets a random theme
        theme: Themes.pick(config.theme, config.set, config.cards),
        random_theme: config.theme == "random",
        set: config.set,
        size: config.cards,
        bombs: Map.get(config, :bombs, 0),
        needed: config.players,
        players: %{},
        public: config.public,
        created_at: now(),
        # The fields of the match that ended with no single winner
        ties: 0,
        # The id of the player on the settings page, see edit_settings/3
        editing: nil,
        # True while the game is in the list of open games. A game with one
        # player is never in it.
        listed: config.public and config.players > 1,
        # The `:level`, the `:user_id` of the player and the `:theme` choice
        # of a game of the campaign, else nil
        campaign: Map.get(config, :campaign)
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
      # A state from before the lists of the settings page
      |> Map.put_new(:public, false)
      |> Map.put_new(:created_at, now())
      |> Map.put_new(:ready_at, now())
      |> Map.put_new(:listed, false)
      # A state from before the accuracy
      |> Map.put_new(:seen, MapSet.new())
      |> Map.update!(:players, fn players ->
        Map.new(players, fn {id, p} ->
          defaults = %{
            correct: 0,
            errors: 0,
            wins: 0,
            dead: false,
            failed_demining: false,
            deminer: false
          }

          {id, Map.merge(defaults, p)}
        end)
      end)
      # A state from before the matches
      |> Map.put_new(:ties, 0)
      |> Map.put(:editing, nil)
      # A state from before the campaign
      |> Map.put_new(:campaign, nil)
      |> Map.put_new(:failed, false)
      # A state from before the bombs
      |> Map.put_new(:bombs, 0)
      |> Map.put_new(:offer, false)
      |> Map.put_new(:demining, false)
      |> Map.update!(:cards, fn cards -> Enum.map(cards, &Map.put_new(&1, :bomb, false)) end)

    store(state)
    {:ok, state}
  end

  @impl true
  def handle_call({:join, pid, _user_id, _name, player_id, _guest_id}, _from, state)
      when is_map_key(state.players, player_id) do
    Process.monitor(pid)
    state = update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})

    # The player is back from the settings page
    if state.editing == player_id do
      state = %{state | editing: nil}
      publish(state)
      {:reply, {:ok, player_id, public(state)}, state}
    else
      store(state)
      {:reply, {:ok, player_id, public(state)}, state}
    end
  end

  # The next game for all players, see `OctomoctoWeb.NextGame`. Not while a
  # player changes the settings.
  def handle_call({:next_game, player_id, page}, _from, %{editing: nil} = state) do
    {id, state} = Octomocto.GameProcess.next_game(state, player_id, page)
    {:reply, id, state}
  end

  def handle_call({:next_game, _player_id, _page}, _from, state), do: {:reply, nil, state}

  # The process of the settings page holds the seat of the player, see
  # `Octomocto.Memory.edit_settings/3`
  def handle_call({:edit_settings, pid, player_id}, _from, state)
      when is_map_key(state.players, player_id) and state.needed > 1 and
             state.finished_at != nil and state.editing in [nil, player_id] do
    Process.monitor(pid)

    state =
      update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})
      |> Map.put(:editing, player_id)

    publish(state)
    {:reply, {:ok, public(state)}, state}
  end

  def handle_call({:edit_settings, _pid, _player_id}, _from, state),
    do: {:reply, {:error, :not_allowed}, state}

  # A new field with the new settings, the same players and the same
  # match. Only the player on the settings page can.
  def handle_call({:change_settings, player_id, settings}, _from, %{editing: player_id} = state)
      when is_binary(player_id) do
    %{theme: theme, set: set, cards: cards} = settings
    bombs = Map.get(settings, :bombs, 0)

    if (theme == "random" or Themes.get(theme) != nil) and set in [2, 3] and
         cards in Board.sizes(theme, set) and bombs in Board.bomb_counts(set, cards) do
      state =
        %{state | theme: Themes.pick(theme, set, cards), set: set, size: cards, editing: nil}
        |> Map.put(:bombs, bombs)
        # A state from before the random theme has no `:random_theme`
        |> Map.put(:random_theme, theme == "random")
        |> new_round()

      publish(state)
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_allowed}, state}
    end
  end

  def handle_call({:change_settings, _player_id, _settings}, _from, state),
    do: {:reply, {:error, :not_allowed}, state}

  def handle_call(:watch, _from, state) do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, _pid, _user_id, _name, _player_id, _guest_id}, _from, state)
      when map_size(state.players) >= state.needed do
    {:reply, {:ok, nil, public(state)}, state}
  end

  # Only the user who started a game of the campaign can play it
  def handle_call(
        {:join, _pid, user_id, _name, _player_id, _guest_id},
        _from,
        %{campaign: %{} = campaign} = state
      )
      when user_id != campaign.user_id do
    {:reply, {:ok, nil, public(state)}, state}
  end

  def handle_call({:join, pid, user_id, name, _player_id, guest_id}, _from, state) do
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
      correct: 0,
      errors: 0,
      # The fields of the match that the player won
      wins: 0,
      # True when the player turned a bomb that was seen, or a card that is
      # not a bomb during a demining (`failed_demining`), see explode/1
      dead: false,
      failed_demining: false,
      # True when the player demined the field
      deminer: false,
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
  def handle_cast({:flip, player_id, card_id}, %{turn: player_id} = state)
      when is_binary(player_id) and card_id >= 0 and state.ready and state.finished_at == nil do
    # The cards of a missed turn stay face up until the next card
    cards = if state.ongoing, do: state.cards, else: Enum.map(state.cards, &turn_down/1)

    case Enum.at(cards, card_id) do
      %{state: :down} = card ->
        known = known_matches(cards, state.seen)
        flip = check_flip(known, state.seen, card_id)
        # The state before the flip, for the rules of the bombs
        before = state

        state =
          %{state | cards: List.replace_at(cards, card_id, %{card | state: :up}), ongoing: true}
          |> count_flip(player_id, flip)
          |> Map.update!(:seen, &MapSet.put(&1, card_id))
          |> Map.update!(:started_at, &(&1 || now()))
          |> after_flip(before, card_id, card, flip, known)
          |> count_win()
          |> save_results()
          |> restart_turn_timer()

        publish(state)
        {:noreply, state}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast({:flip, _player_id, _card_id}, state), do: {:noreply, state}

  # A player can restart at any time, but not while a player changes the
  # settings. A field that is not finished is not saved.
  def handle_cast({:restart, player_id}, %{editing: nil} = state)
      when is_map_key(state.players, player_id) do
    state = state |> pick_theme() |> new_round()
    publish(state)
    {:noreply, state}
  end

  def handle_cast({:restart, _player_id}, state), do: {:noreply, state}

  # A new field uses the theme choice of the player again: with "random",
  # the theme can change
  defp pick_theme(%{campaign: %{level: level, theme: choice}} = state),
    do: %{state | theme: Campaign.pick_theme(Campaign.get(level), choice)}

  defp pick_theme(%{random_theme: true} = state),
    do: %{state | theme: Themes.pick("random", state.set, state.size)}

  defp pick_theme(state), do: state

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Enum.find(state.players, fn {_id, p} -> p.pid == pid end) do
      {player_id, _player} ->
        state = leave(state, player_id)

        # The other players wait for the player on the settings page
        if state.editing == player_id do
          state = %{state | editing: nil}
          publish(state)
          {:noreply, state}
        else
          store(state)
          {:noreply, state}
        end

      nil ->
        {:noreply, state}
    end
  end

  # The player did not join again in the grace time
  def handle_info({:remove, player_id, left}, state) do
    case state.players do
      %{^player_id => %{left: ^left}} ->
        state =
          if state.turn == player_id,
            do: state |> pass_turn() |> restart_turn_timer(),
            else: state

        state = %{state | players: Map.delete(state.players, player_id)}
        state = if state.players == %{}, do: %{state | turn: nil}, else: state
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

  # A new field with zero scores for the same players. The winner of a
  # finished field starts (of the tied players, the one who joined first).
  # After an unfinished field, the player who joined first starts.
  defp new_round(state) do
    order = player_order(state.players)

    turn =
      if state.finished_at,
        do: Enum.max_by(order, &state.players[&1].score),
        else: List.first(order)

    players =
      Map.new(state.players, fn {id, p} ->
        {id,
         %{
           p
           | score: 0,
             correct: 0,
             errors: 0,
             dead: false,
             failed_demining: false,
             deminer: false
         }}
      end)

    %{state | players: players}
    |> Map.delete(:next_game)
    |> new_field()
    |> Map.put(:turn, turn)
    |> make_ready()
  end

  defp new_field(state) do
    theme = Themes.get(state.theme)

    bombs = List.duplicate(%{image: nil, bomb: true, state: :down}, state.bombs)

    cards =
      Enum.take_random(1..theme.cards, div(state.size - state.bombs, state.set))
      |> Enum.flat_map(&List.duplicate(&1, state.set))
      |> Enum.map(&%{image: &1, bomb: false, state: :down})
      |> Kernel.++(bombs)
      |> Enum.shuffle()

    Map.merge(state, %{
      # Groups the saved results of this field
      field_id: Ecto.UUID.generate(),
      cards: cards,
      # The positions of the cards that were face up at some time
      seen: MapSet.new(),
      # The id of the player whose turn it is
      turn: Map.get(state, :turn),
      # True while the player of the turn has turned some cards of a set
      ongoing: false,
      # False until the game has all its players
      ready: false,
      # The time when the game had all its players for this field
      ready_at: nil,
      # The clock starts with the first card
      started_at: nil,
      finished_at: nil,
      # True when a field of the campaign stopped at an error, or when the
      # only player of the game is out
      failed: false,
      # True while the next card of the player of the turn decides if the
      # player demines the field
      offer: false,
      # True while the player of the turn demines the field
      demining: false,
      # The time of the last card, or of the start of the turn
      turn_since: nil,
      turn_ref: nil
    })
  end

  # A game that is ready once does not go back to the list of open games,
  # even when a player leaves later: nobody joins in the middle of a field.
  defp make_ready(%{ready: false} = state) when map_size(state.players) == state.needed do
    %{state | ready: true, ready_at: now(), listed: false} |> restart_turn_timer()
  end

  defp make_ready(state), do: state

  # The first error stops a field of the campaign. The cards of the turn
  # stay face up, so that the player sees the error. The `known` cards that
  # the player had to turn are shown too (as :revealed).
  defp end_turn_or_fail(%{campaign: %{}} = state, :error, known) do
    cards =
      state.cards
      |> Enum.with_index()
      |> Enum.map(fn {card, i} -> if i in known, do: %{card | state: :revealed}, else: card end)

    %{state | cards: cards, failed: true, ongoing: false, finished_at: now()}
  end

  defp end_turn_or_fail(state, _flip, _known), do: state |> end_turn() |> stop_clock()

  # The rules of the bombs for the turned card. `before` is the state
  # before the flip. A try starts when no card of the turn is face up.
  defp after_flip(state, before, card_id, card, flip, known) do
    first = not before.ongoing
    seen = MapSet.member?(before.seen, card_id)

    cond do
      before.offer and card.bomb ->
        state = %{state | offer: false, demining: true}
        if all_bombs_up?(state), do: demine(state), else: state

      before.offer ->
        end_turn_or_fail(%{state | offer: false}, flip, known)

      state.demining and not card.bomb ->
        explode(state)

      state.demining ->
        if all_bombs_up?(state), do: demine(state), else: state

      card.bomb and seen and first and all_bombs_seen?(before) ->
        %{state | demining: true}

      card.bomb and seen ->
        explode(state)

      card.bomb and first and all_bombs_seen?(state) ->
        %{state | offer: true}

      true ->
        end_turn_or_fail(state, flip, known)
    end
  end

  defp all_bombs_seen?(state) do
    state.cards
    |> Enum.with_index()
    |> Enum.all?(fn {card, i} -> not card.bomb or MapSet.member?(state.seen, i) end)
  end

  defp all_bombs_up?(state), do: Enum.all?(state.cards, &(not &1.bomb or &1.state == :up))

  # The player of the turn is out, and the next player who is not out
  # turns. The cards of the turn stay face up, so that all players see the
  # bomb. The field ends when no player is left.
  defp explode(state) do
    state =
      update_in(state.players[state.turn], &%{&1 | dead: true, failed_demining: state.demining})
      |> Map.merge(%{ongoing: false, offer: false, demining: false})

    cond do
      state.needed == 1 -> %{state | failed: true, finished_at: now()}
      Enum.all?(state.players, fn {_id, p} -> p.dead end) -> %{state | finished_at: now()}
      true -> %{state | turn: next_player(state)}
    end
  end

  # All bombs go off the field as a set
  defp demine(state) do
    cards = Enum.map(state.cards, &if(&1.bomb, do: %{&1 | state: :cleared}, else: &1))

    %{state | cards: cards, ongoing: false, demining: false}
    |> update_in([:players, state.turn], &%{&1 | score: &1.score + state.set, deminer: true})
    |> stop_clock()
  end

  # When the face-up cards make a full set, the turn ends: a set goes off
  # the field and the player turns again, and a miss gives the turn to the
  # next player. A bomb is never part of a set.
  defp end_turn(state) do
    up = Enum.filter(state.cards, &(&1.state == :up))

    cond do
      length(up) < state.set ->
        state

      not Enum.any?(up, & &1.bomb) and up |> Enum.map(& &1.image) |> Enum.uniq() |> length() == 1 ->
        cards = Enum.map(state.cards, &if(&1.state == :up, do: %{&1 | state: :cleared}, else: &1))

        %{state | cards: cards, ongoing: false}
        |> update_in([:players, state.turn, :score], &(&1 + state.set))

      true ->
        %{state | ongoing: false, turn: next_player(state)}
    end
  end

  # The positions of the face-down cards that were seen and complete the
  # set of the face-up cards of the turn. nil when the face-up cards cannot
  # make a set (thus before the first flip of a turn, after a miss of a
  # triplet, and with a bomb). The `cards` are the cards before the flip.
  defp known_matches(cards, seen) do
    up = Enum.filter(cards, &(&1.state == :up))

    case up |> Enum.map(& &1.image) |> Enum.uniq() do
      [image] when image != nil ->
        for {%{state: :down, image: ^image}, i} <- Enum.with_index(cards),
            MapSet.member?(seen, i),
            do: i

      _ ->
        nil
    end
  end

  # Tells if the flip of the card is :correct, an :error, or not counted
  # (nil), from the `known` matches (see `known_matches/2`).
  #
  # A flip is counted only when the face-up cards of the turn can still make
  # a set. Then, when a card that completes the set was seen before, the
  # player must turn such a card. When no such card was seen, the player
  # must not turn a card that was seen: it cannot complete the set.
  defp check_flip(known, seen, card_id) do
    cond do
      known == nil -> nil
      known != [] and card_id in known -> :correct
      known != [] -> :error
      MapSet.member?(seen, card_id) -> :error
      true -> nil
    end
  end

  defp count_flip(state, player_id, :correct),
    do: update_in(state.players[player_id].correct, &(&1 + 1))

  defp count_flip(state, player_id, :error),
    do: update_in(state.players[player_id].errors, &(&1 + 1))

  defp count_flip(state, _player_id, nil), do: state

  # Gives the turn to the next player. The cards of an unfinished turn go
  # face down again.
  defp pass_turn(state) do
    cards = if state.ongoing, do: Enum.map(state.cards, &turn_down/1), else: state.cards

    %{
      state
      | cards: cards,
        ongoing: false,
        offer: false,
        demining: false,
        turn: next_player(state)
    }
  end

  defp turn_down(%{state: :up} = card), do: %{card | state: :down}
  defp turn_down(card), do: card

  # The players have their turns in the order in which they joined. A
  # player who is out has no turns. When all others are out, the player of
  # the turn turns again.
  defp next_player(state) do
    order = player_order(state.players)
    {before, rest} = Enum.split_while(order, &(&1 != state.turn))

    (Enum.drop(rest, 1) ++ before ++ Enum.take(rest, 1))
    |> Enum.find(List.first(order), &(not state.players[&1].dead))
  end

  defp player_order(players) do
    players |> Enum.sort_by(fn {_id, p} -> p.joined_at end) |> Enum.map(&elem(&1, 0))
  end

  # The field ends when all sets are off the field. Bombs can stay.
  defp stop_clock(state) do
    if Enum.all?(state.cards, &(&1.state == :cleared or &1.bomb)),
      do: %{state | finished_at: now()},
      else: state
  end

  # A finished field of a match gives a win to the player with the most
  # points, or a tie when more players have the most points
  defp count_win(state) when state.finished_at != nil and state.needed > 1 do
    top = state.players |> Map.values() |> Enum.map(& &1.score) |> Enum.max(fn -> 0 end)

    case Enum.filter(state.players, fn {_id, p} -> p.score == top end) do
      [{id, _p}] -> update_in(state.players[id].wins, &(&1 + 1))
      _ -> Map.update!(state, :ties, &(&1 + 1))
    end
  end

  defp count_win(state), do: state

  # A run of the campaign is also a result, also when it stopped at an
  # error: the score is the cleared cards. The level in the settings keeps
  # it out of the lists of the settings page, which look for the exact
  # settings.
  defp save_results(%{campaign: %{} = campaign} = state) when state.finished_at != nil do
    cleared = Enum.count(state.cards, &(&1.state == :cleared))
    Campaign.save_run(campaign.user_id, campaign.level, cleared)

    settings = %{
      "set" => state.set,
      "cards" => state.size,
      "players" => state.needed,
      "campaign" => campaign.level
    }

    elapsed_ms = state.finished_at - state.started_at

    Memory.save_results(
      state.field_id,
      settings,
      state.theme,
      elapsed_ms,
      Map.values(state.players)
    )

    state
  end

  # A field with bombs has them in the settings, so that its results are
  # not in the lists of the fields with no bombs
  defp save_results(state)
       when state.finished_at != nil and map_size(state.players) == state.needed and
              not state.failed do
    settings = %{"set" => state.set, "cards" => state.size, "players" => state.needed}
    settings = if state.bombs > 0, do: Map.put(settings, "bombs", state.bombs), else: settings
    players = Map.values(state.players)
    elapsed_ms = state.finished_at - state.started_at
    Memory.save_results(state.field_id, settings, state.theme, elapsed_ms, players)
    state
  end

  defp save_results(state), do: state

  # The timer runs only in a game with 2 or more players. A demining has no
  # time limit.
  defp restart_turn_timer(state) when state.ready and state.finished_at == nil do
    if state.needed > 1 and not state.demining do
      ref = make_ref()
      Process.send_after(self(), {:turn_timeout, ref}, @turn_timeout_ms)
      %{state | turn_since: now(), turn_ref: ref}
    else
      # The timer of an earlier turn does not count
      %{state | turn_since: now(), turn_ref: nil}
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
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(state.id), {:memory_state, public(state)})
  end

  @doc """
  The state that clients see, ready to encode as JSON. The images of the
  face-down cards are not in it, so that nobody can look at them. The
  `images` are all images of the field in order, so that the browser can
  load them before the cards turn. They do not show where an image is.
  """
  def public(state) do
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
          # In percent, nil when no flip was counted
          accuracy: Memory.accuracy(p),
          away: p.left != nil,
          wins: p.wins,
          dead: p.dead,
          failed_demining: p.failed_demining,
          deminer: p.deminer
        }
      end)

    # At the end of the field, the bombs that stay show where they were
    cards =
      Enum.map(state.cards, fn card ->
        card_state =
          if card.bomb and card.state == :down and state.finished_at,
            do: :revealed,
            else: card.state

        %{
          state: card_state,
          image: if(card_state != :down and not card.bomb, do: card.image),
          bomb: card_state != :down and card.bomb
        }
      end)

    elapsed_ms =
      if state.started_at, do: (state.finished_at || now()) - state.started_at, else: 0

    %{
      theme: state.theme,
      # True when each new field gets a random theme. A state from before
      # the random theme has no `:random_theme`.
      random_theme: Map.get(state, :random_theme, false),
      set: state.set,
      cards: cards,
      images:
        state.cards
        |> Enum.map(& &1.image)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()
        |> Enum.sort(),
      bombs: state.bombs,
      # The bombs that were face up at some time. When all were, a bomb as
      # the first card of a try starts a demining.
      bombs_seen:
        state.cards
        |> Enum.with_index()
        |> Enum.count(fn {card, i} -> card.bomb and MapSet.member?(state.seen, i) end),
      offer: state.offer,
      demining: state.demining,
      layouts: Enum.map(Board.layouts(state.size), &Tuple.to_list/1),
      waiting: not state.ready,
      # The clock runs from the first card
      started: state.started_at != nil,
      finished: state.finished_at != nil,
      elapsed_ms: elapsed_ms,
      turn: state.turn,
      ongoing: state.ongoing,
      # The time since the last card of the turn, and the time limit (nil
      # when there is none)
      turn_ms: if(state.turn_since, do: now() - state.turn_since, else: 0),
      turn_limit_ms: if(state.needed > 1 and not state.demining, do: @turn_timeout_ms),
      players: players,
      players_needed: state.needed,
      ties: state.ties,
      # The id of the player on the settings page, or nil
      editing: state.editing,
      public: state.public,
      # The level of a game of the campaign, and the number of levels
      campaign: if(state.campaign, do: %{level: state.campaign.level, levels: Campaign.count()}),
      failed: state.failed
    }
  end
end
