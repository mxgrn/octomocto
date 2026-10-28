defmodule Octomocto.Schulte.Game do
  @moduledoc """
  One multiplayer Schulte table: a field with the numbers 1 to 90. The
  layout is `:random` (a new board for each field, see
  `Octomocto.Schulte.Layout`) or `:classic` (always the same board, see
  `Octomocto.Schulte.Classic`). The numbers are in a random order.
  The mode is `:easy` (the client hides the found numbers) or `:normal`
  (the found numbers stay on the board).
  The first player to click the next number gets a point. Nobody can pick
  a number before the countdown is over. The field is finished when all
  numbers are found.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Schulte.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the
  `"schulte_game:<id>"` PubSub topic as `{:schulte_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "schulte_game",
    state_message: :schulte_state,
    lobby_topic: "schulte_lobby",
    store: Octomocto.Schulte.Store,
    context: Octomocto.Schulte

  alias Octomocto.RaceServer
  alias Octomocto.Schulte.{Classic, Layout}

  @total 90
  # The game ends after this number. Dev config sets a small value for easier testing.
  @last Application.compile_env(:octomocto, :schulte_last_number, @total)

  @impl true
  def init_settings(%{layout: layout, mode: mode})
      when layout in [:random, :classic] and mode in [:easy, :normal] do
    %{layout: layout, mode: mode}
  end

  @impl true
  def new_field(state) do
    shapes = if state.layout == :classic, do: Classic.regions(), else: Layout.generate(@total)
    regions = Enum.zip_with(Enum.shuffle(1..@total), shapes, &Map.put(&2, :number, &1))

    Map.merge(state, %{regions: regions, next: 1, found_by: %{}})
  end

  # Only the next number counts
  @impl true
  def handle_move({:pick, player_id, number}, %{next: number} = state)
      when is_map_key(state.players, player_id) and number <= @last do
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

  defp finish_after_last(state) when state.next > @last, do: RaceServer.finish(state)
  defp finish_after_last(state), do: state

  @impl true
  def lobby_settings(state), do: %{layout: state.layout, mode: state.mode}

  @impl true
  def result_settings(state) do
    %{"type" => Atom.to_string(state.layout), "mode" => Atom.to_string(state.mode)}
  end

  @impl true
  def public_field(state) do
    # How narrow a number can get. The classic board has very narrow
    # shapes, where the printed puzzle squeezes the numbers a lot.
    {size, min_stretch} =
      if state.layout == :classic,
        do: {Classic.size(), 0.1},
        else: {Layout.size(), 0.3}

    # Do not show the numbers before the start (also during the countdown),
    # so that nobody can look for them early.
    cells =
      if RaceServer.started?(state),
        do: Enum.map(state.regions, &Map.put(&1, :found_by, state.found_by[&1.number])),
        else: []

    %{
      board: Tuple.to_list(size),
      min_stretch: min_stretch,
      mode: state.mode,
      total: @last,
      next: state.next,
      cells: cells
    }
  end
end
