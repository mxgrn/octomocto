defmodule Octomocto.Afterglow.Game do
  @moduledoc """
  One Afterglow game for one player. A game has 10 rounds. In each round,
  some tiles of a grid light up for a short time, and then the player
  clicks the tiles that were lit. A wrong tile ends the round. After a
  fully correct round, the next round has one tile more, else it has one
  tile less (3 to 20 tiles). The grid grows with the tiles.

  Each correct tile gives points times the tiles of the round. The game
  starts with the tiles of the last round of the last game of the player
  (see `Octomocto.Afterglow.last_level/2`), and a restart starts with the
  tiles of the current round.

  The page shows the tiles itself, checks each click for the score on the
  screen, and sends it here too. The clicks here give the score that the
  game saves. A click before the lit tiles went out does not count.

  The player, the clock and the copy in `Octomocto.Afterglow.Store` are
  the same as in the other games, see `Octomocto.RaceServer`. Each change
  is broadcast on the `"afterglow:<id>"` PubSub topic as
  `{:afterglow_state, state}`, also each correct tile, so that a watcher
  sees it.
  """
  use Octomocto.RaceServer,
    topic: "afterglow",
    state_message: :afterglow_state,
    lobby_topic: "afterglow_lobby",
    store: Octomocto.Afterglow.Store,
    context: Octomocto.Afterglow

  alias Octomocto.RaceServer

  @rounds 10
  @min_level 3
  @max_level 20
  @points 10

  @doc "The tiles of the first round of a new player."
  def min_level, do: @min_level

  @impl true
  def init_settings(%{start_level: level}) when level in @min_level..@max_level,
    do: %{level: level}

  @impl true
  def new_player(player), do: Map.merge(player, %{best_level: nil, perfect: 0, last_level: nil})

  @impl true
  def reset_player(player), do: %{player | best_level: nil, perfect: 0, last_level: nil}

  @impl true
  def new_field(state) do
    state
    |> Map.merge(%{round: 1, history: [], round_at: nil})
    |> new_round(state.level)
  end

  defp new_round(state, level) do
    side = size(level)

    Map.merge(state, %{
      level: level,
      pattern: Enum.take_random(0..(side * side - 1), level),
      found: []
    })
  end

  @doc """
  The number of tiles on each side of the grid for the tiles of a round:
  3 for 3 tiles, 4 for 4 and 5, 5 for 6 to 8, 6 for 9 to 11, and 7 above.
  """
  def size(level) when level <= 3, do: 3
  def size(level) when level <= 5, do: 4
  def size(level) when level <= 8, do: 5
  def size(level) when level <= 11, do: 6
  def size(_level), do: 7

  # More tiles show a bit longer
  defp show_ms(level), do: 800 + 150 * level

  @impl true
  def handle_move({:tap, player_id, round, cell}, %{round: round} = state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if RaceServer.started?(state) and RaceServer.now() >= round_at(state) + show_ms(state.level) and
         cell not in state.found do
      tap(state, player_id, cell)
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move(_move, state), do: {:ignore, :ok, state}

  defp tap(state, player_id, cell) do
    if cell in state.pattern do
      state =
        state
        |> Map.update!(:found, &[cell | &1])
        |> update_in([:players, player_id, :score], &(&1 + @points * state.level))

      if length(state.found) == state.level,
        do: {:publish, :ok, end_round(state, player_id, true)},
        else: {:publish, :ok, state}
    else
      {:publish, :ok, end_round(state, player_id, false)}
    end
  end

  defp end_round(state, player_id, perfect) do
    level = state.level

    state =
      state
      |> Map.update!(:history, &(&1 ++ [%{level: level, perfect: perfect}]))
      |> update_in([:players, player_id], fn player ->
        if perfect,
          do: %{
            player
            | perfect: player.perfect + 1,
              best_level: max(player.best_level || 0, level)
          },
          else: player
      end)

    if state.round == @rounds do
      state
      |> put_in([:players, player_id, :last_level], level)
      |> RaceServer.finish()
    else
      next = if perfect, do: min(level + 1, @max_level), else: max(level - 1, @min_level)

      state
      |> Map.merge(%{round: state.round + 1, round_at: RaceServer.now()})
      |> new_round(next)
    end
  end

  # The first round starts with the clock
  defp round_at(state), do: state.round_at || state.started_at

  @impl true
  def lobby_settings(_state), do: %{}

  @impl true
  def result_settings(_state), do: %{}

  @impl true
  def public_field(state) do
    player =
      Map.values(state.players)
      |> List.first(%{best_level: nil, perfect: 0, last_level: nil})

    started? = RaceServer.started?(state)

    %{
      # Tells a new game from the old one
      field: state.field_id,
      round: state.round,
      rounds: @rounds,
      level: state.level,
      size: size(state.level),
      # Nobody sees the tiles before the start
      pattern: if(started?, do: state.pattern, else: []),
      show_ms: show_ms(state.level),
      points: @points,
      # The time since the start of the round, below zero during the
      # countdown, so that the page can go on after a reload
      round_ms: if(state.started_at, do: RaceServer.now() - round_at(state), else: 0),
      found: state.found,
      history: state.history,
      best_level: player.best_level,
      perfect: player.perfect,
      last_level: player.last_level
    }
  end
end
