defmodule Octomocto.Mahjong.Game do
  @moduledoc """
  One multiplayer mahjong game. All players remove pairs of free tiles from
  the same Turtle board at the same time (see `Octomocto.Mahjong.Board`).
  The first player who removes a pair gets one point. When no pair is
  free, any player can shuffle the tiles. Nobody sees the faces before the
  countdown is over. The board is finished when it is empty.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Mahjong.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the `"mahjong:<id>"`
  PubSub topic as `{:mahjong_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "mahjong",
    state_message: :mahjong_state,
    lobby_topic: "mahjong_lobby",
    store: Octomocto.Mahjong.Store,
    context: Octomocto.Mahjong

  alias Octomocto.RaceServer
  alias Octomocto.Mahjong.Board

  @impl true
  def init_settings(_config), do: %{}

  # A stored board from before the card suits has seasons in their places
  @cards %{
    "season-1" => "card-spades",
    "season-2" => "card-hearts",
    "season-3" => "card-diamonds",
    "season-4" => "card-clubs"
  }

  @impl true
  def restore(state), do: %{state | tiles: Map.new(state.tiles, &season_to_card/1)}

  defp season_to_card({id, tile}), do: {id, Map.update!(tile, :face, &Map.get(@cards, &1, &1))}

  @impl true
  def new_field(state) do
    Map.merge(state, %{
      # The tiles on the board by id, each with its face and position
      tiles: Board.deal(),
      # The last pair that a player removed, with the player and its color
      last: nil,
      # Tells the shuffles apart, so that the pages can show each one
      shuffles: 0
    })
  end

  # Two players can remove the same tile at the same time. The first one
  # gets the pair, and the second one is ignored.
  @impl true
  def handle_move({:remove, player_id, a, b}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil and a != b do
    if RaceServer.started?(state) and removable?(state.tiles, a, b) do
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

      {:publish, :ok, state}
    else
      {:ignore, :ignored, state}
    end
  end

  def handle_move({:remove, _player_id, _a, _b}, state), do: {:ignore, :ignored, state}

  # Only when no pair is free, so that a late second click does nothing
  def handle_move({:shuffle, player_id}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if RaceServer.started?(state) and not Board.free_pair?(state.tiles) do
      state = %{
        state
        | tiles: Board.shuffle(state.tiles),
          last: nil,
          shuffles: state.shuffles + 1
      }

      {:publish, :ok, state}
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move({:shuffle, _player_id}, state), do: {:ignore, :ok, state}

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
    if state.tiles == %{}, do: RaceServer.finish(state), else: state
  end

  @impl true
  def lobby_settings(_state), do: %{}

  @impl true
  def result_settings(_state), do: %{"layout" => "turtle"}

  @impl true
  def public_field(state) do
    started? = RaceServer.started?(state)
    tiles = Enum.map(state.tiles, &public_tile/1)

    %{
      # Do not show the faces before the start (also during the countdown),
      # so that nobody can look for pairs early.
      tiles: if(started?, do: tiles, else: Enum.map(tiles, &%{&1 | face: nil})),
      last: state.last,
      shuffles: state.shuffles,
      # True when no pair is free, so that the players can shuffle
      stuck: started? and state.tiles != %{} and not Board.free_pair?(state.tiles)
    }
  end

  defp public_tile({id, %{face: face, pos: {layer, col, row}}}) do
    %{id: id, face: face, layer: layer, col: col, row: row}
  end
end
