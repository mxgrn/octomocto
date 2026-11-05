defmodule Octomocto.Schulte.Game do
  @moduledoc """
  One multiplayer game of classic Schulte tables: a square grid of `size` ×
  `size` equal cells with the numbers from 1 to `size`² in a random order.
  With `marks`, the client marks the found numbers. Without them (the
  classic rule), the found numbers look the same as the other numbers.
  The first player to click the next number gets a point. Nobody can pick a
  number before the countdown is over. The table is finished when all
  numbers are found.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Schulte.TableStore` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the
  `"schulte_table_game:<id>"` PubSub topic as `{:schulte_state, state}`.

  The topics are not "schulte_game" and "schulte_lobby": a node with older
  code sends the games of Nimble Mosaic (its old name was "Schulte") on
  them.
  """
  use Octomocto.RaceServer,
    topic: "schulte_table_game",
    state_message: :schulte_state,
    lobby_topic: "schulte_table_lobby",
    store: Octomocto.Schulte.TableStore,
    context: Octomocto.Schulte

  alias Octomocto.RaceServer

  @doc "The sizes of the grid: from 5 × 5 to 9 × 9."
  def sizes, do: 5..9

  @impl true
  def init_settings(%{size: size, marks: marks}) when size in 5..9 and is_boolean(marks) do
    %{size: size, marks: marks}
  end

  @impl true
  def new_field(state) do
    Map.merge(state, %{
      numbers: Enum.shuffle(1..(state.size * state.size)),
      next: 1,
      found_by: %{}
    })
  end

  # Only the next number counts
  @impl true
  def handle_move({:pick, player_id, number}, %{next: number} = state)
      when is_map_key(state.players, player_id) do
    if RaceServer.started?(state) do
      state =
        state
        |> update_in([:players, player_id, :score], &(&1 + 1))
        |> Map.update!(:found_by, &Map.put(&1, number, player_id))
        |> Map.put(:next, number + 1)
        |> finish_after_last()

      {:publish, :ok, state}
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move({:pick, _player_id, _number}, state), do: {:ignore, :ok, state}

  defp finish_after_last(state) when state.next > state.size * state.size,
    do: RaceServer.finish(state)

  defp finish_after_last(state), do: state

  @impl true
  def lobby_settings(state), do: %{size: state.size, marks: state.marks}

  @impl true
  def result_settings(state), do: %{"size" => state.size, "marks" => state.marks}

  @impl true
  def public_field(state) do
    # Do not show the numbers before the start (also during the countdown),
    # so that nobody can look for them early. The cells are in the order of
    # the grid: row by row, from the top left.
    cells =
      if RaceServer.started?(state),
        do: Enum.map(state.numbers, &%{number: &1, found_by: state.found_by[&1]}),
        else: []

    %{
      size: state.size,
      marks: state.marks,
      total: state.size * state.size,
      next: state.next,
      cells: cells
    }
  end
end
