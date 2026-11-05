defmodule Octomocto.SchulteTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers
  import Octomocto.AccountsFixtures

  alias Octomocto.Schulte
  alias Octomocto.Schulte.{Game, Result}

  # One player and a 5 × 5 grid, if the test has no `@tag config: [...]`
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(schulte_game(id, tags[:config] || []))

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id}
  end

  test "join/1 gives a grid with each number from 1 to 25 once", %{id: id} do
    {:ok, _player_id, state} = Schulte.join(id)

    assert %{size: 5, total: 25, next: 1, marks: false} = state
    assert state.cells |> Enum.map(& &1.number) |> Enum.sort() == Enum.to_list(1..25)
  end

  @tag config: [size: 9, marks: true]
  test "a 9 × 9 grid has the numbers from 1 to 81", %{id: id} do
    {:ok, _player_id, state} = Schulte.join(id)

    assert %{size: 9, total: 81, marks: true} = state
    assert length(state.cells) == 81
  end

  test "pick/3 counts only the next number", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    Schulte.pick(id, player_id, 2)
    Schulte.pick(id, player_id, 1)

    assert_receive {:schulte_state, %{next: 2, players: [%{score: 1}]} = state}
    assert %{found_by: ^player_id} = Enum.find(state.cells, &(&1.number == 1))
  end

  @tag config: [players: 2]
  test "a finished table saves the result of each player with the settings", %{id: id} do
    user = user_fixture()
    {:ok, first, _} = Schulte.join(id, user.id)
    {:ok, _guest, _} = Schulte.join(id)

    for n <- 1..25, do: Schulte.pick(id, first, n)

    assert_receive {:schulte_state, %{next: 26, elapsed_ms: elapsed_ms}}

    assert [%Result{user_id: nil, score: 0}, %Result{score: 25} = result] =
             Repo.all(from r in Result, order_by: r.score)

    assert result.user_id == user.id
    assert result.settings == %{"size" => 5, "marks" => false, "players" => 2}
    assert result.elapsed_ms == elapsed_ms
  end

  test "best_results/1 and user_results/2 give only the results with the settings" do
    user = user_fixture()
    settings = %{"size" => 6, "marks" => false, "players" => 1}

    Schulte.save_results("a", settings, 9000, [%{user_id: user.id, score: 36}])
    Schulte.save_results("b", %{settings | "size" => 7}, 1000, [%{user_id: user.id, score: 49}])

    assert [%Result{elapsed_ms: 9000}] = Schulte.best_results(settings)

    assert %{latest: [%{result: %Result{game_id: "a"}}], best: %Result{elapsed_ms: 9000}} =
             Schulte.user_results(%{user: user}, settings)
  end
end
