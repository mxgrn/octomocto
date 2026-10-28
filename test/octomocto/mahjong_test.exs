defmodule Octomocto.MahjongTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.Mahjong
  alias Octomocto.Mahjong.{Board, Result, Store}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(mahjong_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, player_id, _} = Mahjong.join(id)
    %{id: id, player_id: player_id}
  end

  # The ids of two free tiles that make a pair, or nil
  defp free_pair(tiles) do
    positions = Board.positions(tiles)
    free = Enum.filter(tiles, fn {_id, tile} -> Board.free?(tile.pos, positions) end)

    Enum.find_value(free, fn {a, tile_a} ->
      Enum.find_value(free, fn {b, tile_b} ->
        a != b and Board.pair?(tile_a.face, tile_b.face) and [a, b]
      end)
    end)
  end

  # Removes pairs, and shuffles when no pair is free, until the board is empty
  defp play_out(id, player_id) do
    tiles = Store.read(id).tiles

    if tiles != %{} do
      case free_pair(tiles) do
        [a, b] -> :ok = Mahjong.remove(id, player_id, a, b)
        nil -> Mahjong.shuffle(id, player_id)
      end

      {:ok, _, _} = Mahjong.watch(id)
      play_out(id, player_id)
    end
  end

  test "a free pair gets the point, and the same pair again is ignored",
       %{id: id, player_id: player_id} do
    [a, b] = free_pair(Store.read(id).tiles)

    assert Mahjong.remove(id, player_id, a, b) == :ok
    assert Mahjong.remove(id, player_id, a, b) == :ignored

    assert {:ok, nil, %{players: [%{score: 1}], last: %{player_id: ^player_id}}} =
             Mahjong.watch(id)
  end

  test "an empty board finishes the game and saves the result",
       %{id: id, player_id: player_id} do
    play_out(id, player_id)

    assert {:ok, nil, %{finished: true}} = Mahjong.watch(id)

    assert [%Result{score: 72, settings: %{"layout" => "turtle", "players" => 1}}] =
             Repo.all(Result)
  end

  test "a stored board from before the card suits gets cards in the places of the seasons",
       %{id: id} do
    state = Store.read(id)
    tile_id = state.tiles |> Map.keys() |> hd()
    stop_supervised!(Mahjong.Game)
    Store.write(put_in(state.tiles[tile_id].face, "season-1"))
    # The name of the game is free only after :global sees the exit
    _ = :sys.get_state(:global_name_server)

    {:ok, _, _} = Mahjong.watch(id)

    assert Store.read(id).tiles[tile_id].face == "card-spades"
  end
end
