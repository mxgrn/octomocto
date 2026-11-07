defmodule Octomocto.Afterglow.TurnsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.{Afterglow, Lobby, Match}
  alias Octomocto.Afterglow.{Result, TurnGame, TurnStore, Turns}

  # Two players who are in, on a 4 × 4 grid
  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(afterglow_turns_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, first, _} = Turns.join(id)
    {:ok, second, _} = Turns.join(id)
    %{id: id, pid: pid, first: first, second: second}
  end

  defp watch(id) do
    {:ok, nil, state} = Turns.watch(id)
    state
  end

  # The player clicks all tiles of the pattern and then adds the cell
  defp turn(id, player_id, pattern, cell) do
    for tile <- pattern, do: Turns.tap(id, player_id, tile)
    Turns.tap(id, player_id, cell)
    pattern ++ [cell]
  end

  test "the first player only adds a tile, and the pattern does not show", %{
    id: id,
    first: first,
    second: second
  } do
    Turns.tap(id, second, 0)
    Turns.tap(id, first, 5)

    assert %{length: 1, pattern: nil, turn: ^second, last_tap: %{cell: 5, ok: true}} = watch(id)
  end

  test "the full pattern gives its length as the score, then the player adds a tile",
       %{id: id, first: first, second: second} do
    pattern = turn(id, first, [], 5)

    turn(id, second, pattern, 6)

    assert %{length: 2, turn: ^first, found: [], players: [%{score: 0}, %{score: 1}]} = watch(id)
  end

  test "after a new tile, all browsers get the full pattern to flash",
       %{id: id, first: first, second: second} do
    Phoenix.PubSub.subscribe(Octomocto.PubSub, TurnGame.topic(id))
    pattern = turn(id, first, [], 5)

    turn(id, second, pattern, 6)

    assert_receive {:afterglow_turns_flash, [5, 6]}
  end

  test "a wrong tile puts the player out, and the last player in wins and is saved",
       %{id: id, first: first, second: second} do
    turn(id, first, [], 5)

    Turns.tap(id, second, 6)

    assert %{finished: true, winners: [^first], pattern: [5]} = watch(id)

    assert [%Result{settings: %{"players" => 2, "size" => 4}, last_level: nil}, _] =
             Repo.all(Result)
  end

  test "the next single-player game does not start from a game with turns",
       %{id: id, first: first, second: second} do
    turn(id, first, [], 5)
    Turns.tap(id, second, 6)
    assert %{finished: true} = watch(id)

    [%Result{guest_id: guest_id} | _] = Repo.all(Result)
    assert Afterglow.last_level(nil, guest_id) == nil
  end

  test "at half of the grid, all players who are still in share the win",
       %{id: id, first: first, second: second} do
    pattern =
      Enum.reduce(0..6, [], fn cell, pattern ->
        player = if rem(cell, 2) == 0, do: first, else: second
        turn(id, player, pattern, cell)
      end)

    turn(id, second, pattern, 7)

    assert %{finished: true, length: 8, winners: winners} = watch(id)
    assert Enum.sort(winners) == Enum.sort([first, second])
    assert %{ties: 1} = watch(id)
  end

  test "the player who does nothing until the turn timer runs out is out",
       %{id: id, pid: pid, second: second} do
    send(pid, {:turn_timeout, TurnStore.read(id).turn_ref})

    assert %{finished: true, winners: [^second]} = watch(id)
  end

  test "with 3 players, the grid must be at least 5 × 5" do
    refute TurnGame.valid_size?(4, 3)
    assert TurnGame.valid_size?(5, 3)
  end

  test "after the end, a player starts the next game on the next larger grid at once",
       %{id: id, first: first, second: second} do
    turn(id, first, [], 5)
    Turns.tap(id, second, 6)

    assert :ok = Turns.play_larger(id, second)

    assert %{size: 5, finished: false, waiting: false, editing: nil, players: [_, _]} = watch(id)
  end

  test "a player changes the grid of the next game of a match",
       %{id: id, first: first, second: second} do
    turn(id, first, [], 5)
    Turns.tap(id, second, 6)

    {:ok, _} = Match.edit_settings(TurnGame, id, second)
    :ok = Match.change_settings(TurnGame, id, second, %{size: 5})

    assert %{size: 5, finished: false, length: 0, players: players} = watch(id)
    assert Enum.map(players, &{&1.id, &1.wins}) == [{first, 1}, {second, 0}]
  end

  test "a public game is in the lists of the settings page with its grid" do
    Lobby.subscribe(TurnGame)
    id = "public-#{System.unique_integer([:positive])}"
    start_supervised!(afterglow_turns_game(id, public: true, size: 5), id: :public)

    {:ok, _, _} = Turns.join(id)

    assert_receive {:lobby_changed, TurnGame, ^id, %{status: :open, settings: %{size: 5}}}
  end
end
