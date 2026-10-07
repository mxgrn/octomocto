defmodule Octomocto.SchulteTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.Schulte
  alias Octomocto.Schulte.{Game, Result}

  # One player, if the test has no `@tag players: n`
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!({Game, {id, :random, tags[:players] || 1}})
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id}
  end

  test "join/1 gives a field with each number from 1 to 90 once", %{id: id} do
    {:ok, player_id, state} = Schulte.join(id)

    assert state.cells |> Enum.map(& &1.number) |> Enum.sort() == Enum.to_list(1..90)
    assert state.next == 1
    assert [%{id: ^player_id, score: 0}] = state.players
  end

  test "join/1 fails for an unknown game" do
    assert Schulte.join("unknown") == {:error, :not_found}
  end

  test "pick/3 of the next number gives a point and marks the number", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    Schulte.pick(id, player_id, 1)

    assert_receive {:schulte_state, %{next: 2, players: [%{score: 1}]} = state}
    assert %{found_by: ^player_id} = Enum.find(state.cells, &(&1.number == 1))
  end

  test "pick/3 of a wrong number does nothing", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    Schulte.pick(id, player_id, 2)
    Schulte.pick(id, player_id, 1)

    assert_receive {:schulte_state, %{next: 2, players: [%{score: 1}]}}
  end

  @tag players: 2
  test "the race starts when all players are in", %{id: id} do
    {:ok, first, state} = Schulte.join(id)
    assert %{waiting: true, cells: [], elapsed_ms: 0} = state

    Schulte.pick(id, first, 1)
    {:ok, _second, state} = Schulte.join(id)

    assert %{waiting: false, next: 1} = state
    assert length(state.cells) == 90
  end

  test "a process that joins a full game only watches", %{id: id} do
    {:ok, _player_id, _} = Schulte.join(id)

    assert {:ok, nil, %{players: [_]}} = Schulte.join(id)
  end

  @tag players: 2
  test "only the first player to pick the number gets the point", %{id: id} do
    {:ok, first, _} = Schulte.join(id)
    {:ok, second, _} = Schulte.join(id)

    Schulte.pick(id, first, 1)
    Schulte.pick(id, second, 1)
    Schulte.pick(id, second, 2)

    assert_receive {:schulte_state, %{next: 3, players: [%{score: 1}, %{score: 1}]}}
  end

  test "the clock stops after all numbers are found", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    for n <- 1..90, do: Schulte.pick(id, player_id, n)

    assert_receive {:schulte_state, %{next: 91, elapsed_ms: elapsed_ms}}
    # Let some time pass, so that a running clock would show a later time
    Process.sleep(5)
    assert {:ok, _, %{elapsed_ms: ^elapsed_ms}} = Schulte.join(id)
  end

  test "restart/1 starts a new field with zero scores after all numbers are found", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    for n <- 1..90, do: Schulte.pick(id, player_id, n)
    Schulte.restart(id)

    assert_receive {:schulte_state, %{next: 91, players: [%{score: 90}]}}
    assert_receive {:schulte_state, %{next: 1, players: [%{score: 0}]}}
  end

  @tag players: 2
  test "a finished field saves the result of each player", %{id: id} do
    user = user_fixture()
    {:ok, first, _} = Schulte.join(id, user.id)
    {:ok, _guest, _} = Schulte.join(id)

    for n <- 1..90, do: Schulte.pick(id, first, n)

    assert_receive {:schulte_state, %{next: 91, elapsed_ms: elapsed_ms}}

    assert [
             %Result{user_id: nil, score: 0} = guest,
             %Result{user_id: user_id, score: 90} = player
           ] = Repo.all(from r in Result, order_by: r.score)

    assert user_id == user.id
    assert player.settings == %{"type" => "random", "players" => 2}
    assert player.elapsed_ms == elapsed_ms
    assert guest.game_id == player.game_id
  end

  @tag players: 2
  test "a finished field is not saved when a player has left", %{id: id} do
    {:ok, first, _} = Schulte.join(id)
    Task.async(fn -> Schulte.join(id) end) |> Task.await()

    assert_receive {:schulte_state, %{players: [_]}}
    for n <- 1..90, do: Schulte.pick(id, first, n)

    assert_receive {:schulte_state, %{next: 91}}
    assert Repo.all(Result) == []
  end

  describe "leaderboard/1" do
    @solo %{"type" => "classic", "players" => 1}
    @duo %{"type" => "classic", "players" => 2}

    test "shows only the results with the given settings" do
      user = user_fixture()
      Schulte.save_results("a", @solo, 1000, [%{user_id: user.id, score: 90}])
      Schulte.save_results("b", @duo, 2000, [%{user_id: user.id, score: 90}])

      assert %{latest: [%{game_id: "a"}], best: [%{game_id: "a"}]} = Schulte.leaderboard(@solo)
    end

    test "latest games show all players of a field, the newest field first" do
      user = user_fixture()
      Schulte.save_results("old", @duo, 1000, [%{user_id: user.id, score: 90}])

      Schulte.save_results("new", @duo, 2000, [
        %{user_id: nil, score: 30},
        %{user_id: user.id, score: 60}
      ])

      assert %{latest: [new, old]} = Schulte.leaderboard(@duo)
      assert %{game_id: "new", elapsed_ms: 2000} = new
      assert [%{score: 60, user: %{id: user_id}}, %{score: 30, user: nil}] = new.players
      assert user_id == user.id
      assert old.game_id == "old"
    end

    test "best results show the best time of each user, the fastest first, without guests" do
      [fast, slow] = [user_fixture(), user_fixture()]
      Schulte.save_results("a", @solo, 3000, [%{user_id: fast.id, score: 90}])
      Schulte.save_results("b", @solo, 1000, [%{user_id: fast.id, score: 90}])
      Schulte.save_results("c", @solo, 2000, [%{user_id: slow.id, score: 90}])
      Schulte.save_results("d", @solo, 500, [%{user_id: nil, score: 90}])

      assert %{best: best} = Schulte.leaderboard(@solo)
      assert Enum.map(best, &{&1.user.id, &1.elapsed_ms}) == [{fast.id, 1000}, {slow.id, 2000}]
    end
  end
end
