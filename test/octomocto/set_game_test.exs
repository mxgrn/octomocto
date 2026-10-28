defmodule Octomocto.SetGameTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.SetGame
  alias Octomocto.SetGame.{Deck, Result, Store}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(set_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, player_id, _} = SetGame.join(id)
    %{id: id, player_id: player_id}
  end

  defp triples(table), do: for(a <- table, b <- table, c <- table, a < b and b < c, do: [a, b, c])

  defp find_set(table), do: table |> triples() |> Enum.find(&Deck.set?/1)

  # Claims sets until the game ends
  defp play_out(id, player_id) do
    state = Store.read(id)

    if state.finished_at == nil do
      SetGame.claim(id, player_id, find_set(state.table))
      {:ok, _, _} = SetGame.watch(id)
      play_out(id, player_id)
    end
  end

  test "a set gets the point and leaves the table, and a wrong claim changes nothing",
       %{id: id, player_id: player_id} do
    table = Store.read(id).table
    set = find_set(table)

    SetGame.claim(id, player_id, Enum.reject(triples(table), &Deck.set?/1) |> hd())
    SetGame.claim(id, player_id, set)

    {:ok, nil, state} = SetGame.watch(id)
    assert %{players: [%{score: 1}], last_set: %{player_id: ^player_id, cards: ^set}} = state
    assert Enum.all?(set, &(&1 not in state.table))
  end

  test "the game ends when no set is left, and saves the result",
       %{id: id, player_id: player_id} do
    play_out(id, player_id)

    assert {:ok, nil, %{finished: true}} = SetGame.watch(id)
    assert [%Result{settings: %{"mode" => "easy", "players" => 1}}] = Repo.all(Result)
  end

  test "a stored game from before the modes is in the normal mode", %{id: id} do
    state = Store.read(id)
    stop_supervised!(SetGame.Game)
    Store.write(Map.delete(state, :mode))
    # The name of the game is free only after :global sees the exit
    _ = :sys.get_state(:global_name_server)

    {:ok, _, _} = SetGame.watch(id)

    assert Store.read(id).mode == "normal"
  end
end
