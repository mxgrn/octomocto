defmodule Octomocto.SchulteTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  import Octomocto.AccountsFixtures

  alias Octomocto.{Lobby, Schulte}
  alias Octomocto.Schulte.{Game, Result, Store}

  # One player and a private game, if the test has no `@tag players: n` or
  # `@tag public: true`. A `@tag config: [...]` changes more of the config.
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"
    config = [players: tags[:players] || 1, public: tags[:public] || false]
    pid = start_supervised!(schulte_game(id, config ++ (tags[:config] || [])))

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id, pid: pid}
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

  @tag config: [countdown_ms: :timer.minutes(1)]
  test "nobody sees or picks the numbers during the countdown", %{id: id} do
    {:ok, player_id, state} = Schulte.join(id)
    assert %{waiting: false, cells: []} = state

    Schulte.pick(id, player_id, 1)

    assert {:ok, nil, %{next: 1, cells: []}} = Schulte.watch(id)
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

  test "restart/2 starts a new field with zero scores after all numbers are found", %{id: id} do
    {:ok, player_id, _} = Schulte.join(id)

    for n <- 1..90, do: Schulte.pick(id, player_id, n)
    Schulte.restart(id, player_id)

    assert_receive {:schulte_state, %{next: 91, players: [%{score: 90}]}}
    assert {:ok, nil, %{next: 1, players: [%{score: 0}]}} = Schulte.watch(id)
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
    assert player.settings == %{"type" => "random", "mode" => "easy", "players" => 2}
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

  describe "players" do
    @tag players: 4
    test "each player gets a different color", %{id: id} do
      for _ <- 1..4, do: {:ok, _, _} = Schulte.join(id)

      {:ok, nil, state} = Schulte.watch(id)
      assert state.players |> Enum.map(& &1.color_name) |> Enum.uniq() |> length() == 4
    end

    @tag players: 2
    test "watch/1 gives the state without a seat, also when the game has a free seat",
         %{id: id} do
      assert {:ok, nil, %{players: []}} = Schulte.watch(id)
      assert {:ok, player_id, _} = Schulte.join(id)
      assert is_binary(player_id)
    end

    test "join/5 with the id of a player gives the same player back", %{id: id} do
      {:ok, player_id, _} = Schulte.join(id)
      Schulte.pick(id, player_id, 1)

      assert {:ok, ^player_id, %{players: [%{id: ^player_id, score: 1}]}} =
               Schulte.join(id, nil, nil, player_id)
    end

    @tag config: [rejoin_grace_ms: :timer.minutes(1)]
    test "a player is away during the grace time, and can join again", %{id: id, pid: pid} do
      task = Task.async(fn -> Schulte.join(id) end)
      {:ok, player_id, _} = Task.await(task)
      ref = Process.monitor(task.pid)
      assert_receive {:DOWN, ^ref, :process, _, _}
      _ = :sys.get_state(pid)

      assert {:ok, nil, %{players: [%{away: true}]}} = Schulte.watch(id)

      assert {:ok, ^player_id, %{players: [%{away: false}]}} =
               Schulte.join(id, nil, nil, player_id)
    end

    @tag players: 2
    test "a player is removed after the process of the player stops", %{id: id} do
      {:ok, first, _} = Schulte.join(id)
      assert_receive {:schulte_state, %{players: [_]}}

      Task.async(fn -> Schulte.join(id) end) |> Task.await()

      assert_receive {:schulte_state, %{players: [_, _]}}
      assert_receive {:schulte_state, %{players: [%{id: ^first}]}}
    end

    test "restart/2 from a process that is not a player does nothing", %{id: id} do
      {:ok, player_id, _} = Schulte.join(id)
      Schulte.pick(id, player_id, 1)

      Schulte.restart(id, "stranger")

      assert {:ok, nil, %{next: 2, players: [%{score: 1}]}} = Schulte.watch(id)
    end
  end

  describe "lobby" do
    setup do
      Lobby.subscribe(Game)
    end

    @tag players: 2, public: true
    test "a public game is an open game until it has all its players, then an ongoing game",
         %{id: id} do
      {:ok, _, _} = Schulte.join(id)

      assert_receive {:lobby_changed, Game, ^id, entry}

      assert %{
               status: :open,
               seats_left: 1,
               players_needed: 2,
               settings: %{layout: :random, mode: :easy},
               players: [%{score: 0, away: false}]
             } = entry

      {:ok, _, _} = Schulte.join(id)

      assert_receive {:lobby_changed, Game, ^id, %{status: :ongoing, finished: false}}
    end

    @tag public: true
    test "a public game for one player is only an ongoing game, also when it is finished",
         %{id: id} do
      {:ok, player_id, _} = Schulte.join(id)

      assert_receive {:lobby_changed, Game, ^id, %{status: :ongoing, finished: false}}

      for n <- 1..90, do: Schulte.pick(id, player_id, n)

      assert_receive {:lobby_changed, Game, ^id,
                      %{status: :ongoing, finished: true, players: [%{score: 90}]}}
    end

    test "a private game sends no rows", %{id: id} do
      {:ok, _, _} = Schulte.join(id)

      refute_receive {:lobby_changed, Game, ^id, _}
    end

    @tag public: true
    test "Lobby.entries/2 gives the row of a running public game", %{id: id} do
      {:ok, _, _} = Schulte.join(id)

      assert %{status: :ongoing} = Enum.find(Lobby.entries(Game, Store), &(&1.id == id))
    end

    @tag public: true
    test "a game leaves the lists when its process stops", %{id: id} do
      {:ok, _, _} = Schulte.join(id)

      stop_supervised!(Game)

      assert_receive {:lobby_changed, Game, ^id, nil}
    end
  end

  describe "store" do
    test "a game starts again from its copy in the store when its process stops",
         %{id: id, pid: pid} do
      {:ok, player_id, %{cells: cells}} = Schulte.join(id)
      Schulte.pick(id, player_id, 1)
      assert_receive {:schulte_state, %{next: 2}}

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      # The name of the game is free only after :global sees the exit
      _ = :sys.get_state(:global_name_server)

      assert {:ok, nil, %{next: 2, cells: restored}} = Schulte.watch(id)
      assert Enum.map(restored, & &1.number) == Enum.map(cells, & &1.number)
    end

    test "a game with no players stops at the idle check and leaves the store",
         %{id: id, pid: pid} do
      ref = Process.monitor(pid)

      send(pid, :idle_check)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert Store.read(id) == nil
    end

    test "a game with players keeps running at the idle check", %{id: id, pid: pid} do
      {:ok, _, _} = Schulte.join(id)

      send(pid, :idle_check)

      assert {:ok, nil, %{players: [_]}} = Schulte.watch(id)
    end
  end

  describe "user_results/2" do
    @duo %{"type" => "random", "mode" => "easy", "players" => 2}

    test "gives the latest results with all players, the user first, and the best result without guests" do
      [user, other] = [user_fixture(), user_fixture()]

      Schulte.save_results("a", @duo, 1000, [
        %{user_id: other.id, score: 50},
        %{user_id: user.id, score: 40}
      ])

      Schulte.save_results("b", @duo, 500, [
        %{user_id: user.id, score: 60},
        %{user_id: nil, score: 30}
      ])

      %{latest: latest, best: best} = Schulte.user_results(%{user: user}, @duo)

      assert [
               %{result: %{game_id: "b"}, players: [mine_b, %{user_id: nil}]},
               %{result: %{game_id: "a"}, players: [mine_a, theirs]}
             ] = latest

      assert mine_b.user_id == user.id
      assert mine_a.user_id == user.id
      assert theirs.user_id == other.id
      assert %{game_id: "a"} = best
    end
  end

  describe "best_results/1" do
    @solo %{"type" => "classic", "mode" => "easy", "players" => 1}
    @duo %{"type" => "classic", "mode" => "easy", "players" => 2}

    test "shows only the results with the given settings" do
      user = user_fixture()
      Schulte.save_results("a", @solo, 1000, [%{user_id: user.id, score: 90}])
      Schulte.save_results("b", @duo, 2000, [%{user_id: user.id, score: 90}])

      assert [%{game_id: "a"}] = Schulte.best_results(@solo)
    end

    test "best results show the best time of each user, the fastest first, without guests" do
      [fast, slow] = [user_fixture(), user_fixture()]
      Schulte.save_results("a", @solo, 3000, [%{user_id: fast.id, score: 90}])
      Schulte.save_results("b", @solo, 1000, [%{user_id: fast.id, score: 90}])
      Schulte.save_results("c", @solo, 2000, [%{user_id: slow.id, score: 90}])
      Schulte.save_results("d", @solo, 500, [%{user_id: nil, score: 90}])

      best = Schulte.best_results(@solo)
      assert Enum.map(best, &{&1.user.id, &1.elapsed_ms}) == [{fast.id, 1000}, {slow.id, 2000}]
    end
  end
end
