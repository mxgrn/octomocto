defmodule Octomocto.Afterglow.TurnGame do
  @moduledoc """
  One Afterglow game for 2 to 4 players, who take turns on one square
  grid. The players make one pattern of tiles together.

  The first player of a game only adds a tile of their choice. In each
  turn after that, the player clicks all tiles of the pattern, in any
  order, and then adds a new tile. The pattern never shows again: the
  other players watch each turn and remember it. A wrong tile puts the
  player out, and the pattern stays for the next player. A player who does
  nothing for some time is also out. When only one player is still in,
  that player wins. When half of the grid is in the pattern, the game ends,
  and all players who are still in share the win.

  The score of a player is the length of the longest pattern that the
  player clicked fully. Each click is in the state as the `last_tap`, so
  that the browsers of the other players show it. After each new tile, all
  browsers flash the full pattern once. When the game ends with
  all its players, it saves the score of each player (see
  `Octomocto.Afterglow.save_results/4`).

  The players, the turns, the lists of the settings page and the copy in
  `Octomocto.Afterglow.TurnStore` are the same as in the other games with
  turns, see `Octomocto.TurnServer`. Each change is broadcast on the
  `"afterglow_turns:<id>"` PubSub topic as `{:afterglow_turns_state, state}`.
  """
  use Octomocto.TurnServer,
    topic: "afterglow_turns",
    state_message: :afterglow_turns_state,
    lobby_topic: "afterglow_turns_lobby",
    store: Octomocto.Afterglow.TurnStore

  alias Octomocto.{Afterglow, GameEnd, TurnServer}

  @sizes 4..10

  @doc "The sizes of the grid: the number of tiles on each side."
  def sizes, do: @sizes

  @doc """
  The smallest grid for the number of players: more players wait longer
  for their turn, so they get more space.
  """
  def min_size(players) when players in 2..4, do: players + 2

  @doc "True when the grid size is allowed for the number of players."
  def valid_size?(size, players) when players in 2..4,
    do: size in @sizes and size >= min_size(players)

  def valid_size?(_size, _players), do: false

  @doc "The length of the pattern that ends the game: half of the grid, rounded up."
  def target(size), do: div(size * size + 1, 2)

  @impl true
  def init_settings(%{size: size, players: players}) do
    true = valid_size?(size, players)
    # Counts the taps, so that a browser knows a new tap
    %{size: size, taps: 0}
  end

  @impl true
  def new_field(state) do
    Map.merge(state, %{
      # The tiles, from 0, in the order in which the players added them
      pattern: [],
      # The tiles of the pattern that the player of the turn clicked. When
      # it has all of them, the player adds a tile.
      found: [],
      # The ids of the players who won: one, or all players who were still
      # in when half of the grid was in the pattern
      winners: [],
      # The last tile that a player clicked, see public_field/1
      last_tap: nil
    })
  end

  # The next game of a match, see `Octomocto.Match`
  @impl true
  def change_settings(%{size: size}, state) do
    if valid_size?(size, state.needed), do: {:ok, %{state | size: size}}, else: :error
  end

  def change_settings(_settings, _state), do: :error

  # One winner gets a win. All players who were still in at the end share it.
  @impl true
  def winners(state), do: state.winners

  # The place in the order in which the players went out, or nil while the
  # player is in
  @impl true
  def new_player(player), do: Map.put(player, :out, nil)

  @impl true
  def reset_player(player), do: %{player | out: nil}

  @impl true
  def handle_move({:tap, player_id, cell}, %{turn: player_id} = state)
      when is_binary(player_id) and is_integer(cell) and cell >= 0 and
             cell < state.size * state.size and state.ready and state.finished_at == nil do
    cond do
      length(state.found) < length(state.pattern) -> recall(state, cell)
      cell in state.pattern -> {:ignore, :ok, state}
      true -> {:publish, :ok, add_tile(state, cell)}
    end
  end

  def handle_move(_move, state), do: {:ignore, :ok, state}

  # The player of the turn did nothing for too long, or left the game: the
  # player is out. Before the start and after the end, the turn only goes
  # to the next player.
  @impl true
  def pass_turn(state) when state.ready and state.finished_at == nil do
    state |> put_out() |> maybe_finish()
  end

  def pass_turn(state), do: next_turn(state)

  # When only one player is still in, the game ends
  @impl true
  def after_remove(state), do: maybe_finish(state)

  # The player of the turn clicks a tile of the pattern. A tile that the
  # player clicked already does not count.
  defp recall(state, cell) do
    cond do
      cell in state.found ->
        {:ignore, :ok, state}

      cell in state.pattern ->
        state = %{state | found: [cell | state.found]} |> tap(cell, true)

        state =
          if length(state.found) == length(state.pattern),
            do: update_in(state.players[state.turn].score, &max(&1, length(state.pattern))),
            else: state

        {:publish, :ok, TurnServer.restart_turn_timer(state)}

      true ->
        {:publish, :ok, state |> tap(cell, false) |> put_out() |> maybe_finish()}
    end
  end

  # The player of the turn adds a tile, and the turn goes to the next
  # player. All browsers flash the full pattern once (see `flash/1`). At
  # half of the grid, the game ends.
  defp add_tile(state, cell) do
    state = %{state | pattern: state.pattern ++ [cell]} |> tap(cell, true)
    flash(state)

    if length(state.pattern) >= target(state.size) do
      left = for {id, p} <- state.players, p.out == nil, do: id
      finish(state, left)
    else
      state |> next_turn() |> TurnServer.restart_turn_timer()
    end
  end

  # The pattern goes to the browsers in a message of its own, before the
  # new state, so that it is never in the state that the clients see
  defp flash(state) do
    Phoenix.PubSub.broadcast(
      Octomocto.PubSub,
      topic(state.id),
      {:afterglow_turns_flash, state.pattern}
    )
  end

  defp tap(state, cell, ok) do
    taps = state.taps + 1
    %{state | taps: taps, last_tap: %{n: taps, cell: cell, player: state.turn, ok: ok}}
  end

  # The player of the turn is out, and the turn goes to the next player
  # who is in
  defp put_out(state) do
    place = Enum.count(state.players, fn {_id, p} -> p.out != nil end) + 1

    state
    |> update_in([:players, state.turn], &%{&1 | out: place})
    |> next_turn()
    |> TurnServer.restart_turn_timer()
  end

  # The next player who is in starts again from the first tile
  defp next_turn(state), do: %{state | found: [], turn: next_player(state)}

  # The game ends when only one player is still in
  defp maybe_finish(state) when state.ready and state.finished_at == nil do
    case for({id, p} <- state.players, p.out == nil, do: id) do
      [_, _ | _] -> state
      left -> finish(state, left)
    end
  end

  defp maybe_finish(state), do: state

  defp finish(state, winners) do
    %{state | finished_at: TurnServer.now(), winners: winners, turn: List.first(winners)}
    |> TurnServer.restart_turn_timer()
    |> save_results()
  end

  # The players have their turns in the order in which they joined. With
  # nobody in, the turn stays.
  defp next_player(state) do
    order = Octomocto.Seats.order(state)
    {before, rest} = Enum.split_while(order, &(&1 != state.turn))

    # The players after the current one, then the ones before it, then the
    # current one
    (Enum.drop(rest, 1) ++ before ++ Enum.take(rest, 1))
    |> Enum.find(state.turn, &(state.players[&1].out == nil))
  end

  defp save_results(state) when map_size(state.players) == state.needed do
    settings = %{"players" => state.needed, "size" => state.size}

    players =
      for p <- Map.values(state.players),
          do: Map.merge(p, %{best_level: p.score, last_level: nil, perfect: 0})

    Afterglow.save_results(state.field_id, settings, nil, players)
    GameEnd.finished(state)
  end

  defp save_results(state), do: state

  @impl true
  def lobby_settings(state), do: %{size: state.size}

  @impl true
  def public_player(player), do: %{out: player.out}

  # The pattern is not in the public state: the players must remember it.
  # It shows only after the end.
  @impl true
  def public_field(state) do
    finished = state.finished_at != nil

    %{
      size: state.size,
      target: target(state.size),
      pattern: if(finished, do: state.pattern),
      length: length(state.pattern),
      found: state.found,
      winners: state.winners,
      last_tap: state.last_tap,
      # A larger grid for a game where more than one player was still in
      # at the end
      next_size: if(state.size < Enum.max(@sizes), do: state.size + 1)
    }
  end
end
