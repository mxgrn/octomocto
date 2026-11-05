defmodule Octomocto.Trains.GameTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers
  import Octomocto.AccountsFixtures

  alias Octomocto.{Lobby, Trains}
  alias Octomocto.Friends.Follow
  alias Octomocto.Trains.Game

  # One player and a private game, if the test has no `@tag players: n` or
  # `@tag public: true`
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"

    config =
      [players: tags[:players] || 1, public: tags[:public] || false] ++ (tags[:config] || [])

    pid = start_supervised!(trains_game(id, config))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id, pid: pid}
  end

  test "join/5 with the id of a player gives the same player back", %{id: id} do
    {:ok, player_id, _} = Trains.join(id)

    assert {:ok, ^player_id, %{players: [%{id: ^player_id}]}} =
             Trains.join(id, nil, nil, player_id)
  end

  @tag config: [rejoin_grace_ms: :timer.minutes(1)]
  test "a player can join again after its process stops", %{id: id, pid: pid} do
    task = Task.async(fn -> Trains.join(id) end)
    {:ok, player_id, _} = Task.await(task)
    ref = Process.monitor(task.pid)
    assert_receive {:DOWN, ^ref, :process, _, _}
    _ = :sys.get_state(pid)

    assert {:ok, ^player_id, %{players: [%{id: ^player_id}]}} =
             Trains.join(id, nil, nil, player_id)
  end

  @tag players: 4
  test "a new player takes the first free slot and its color", %{id: id} do
    {:ok, _, _} = Trains.join(id)
    assert_receive {:trains_state, %{players: [_]}}
    Task.async(fn -> Trains.join(id) end) |> Task.await()
    assert_receive {:trains_state, %{players: [_, _]}}
    assert_receive {:trains_state, %{players: [_]}}

    {:ok, _, %{players: [_, second]}} = Trains.join(id)

    assert %{slot: 1, color_name: "sky"} = second
  end

  @tag players: 2
  test "a player is removed after the process of the player stops", %{id: id} do
    {:ok, first, _} = Trains.join(id)
    assert_receive {:trains_state, %{players: [_]}}

    Task.async(fn -> Trains.join(id) end) |> Task.await()

    assert_receive {:trains_state, %{players: [_, _]}}
    assert_receive {:trains_state, %{players: [%{id: ^first}]}}
  end

  @tag players: 2
  test "a finished round makes friends of the creator and a player from a shared link",
       %{id: id} do
    [creator, friend] = for _ <- 1..2, do: user_fixture()
    {:ok, first, _} = Trains.join(id, creator.id)
    {:ok, _, %{seed: seed}} = Trains.join(id, friend.id)

    Trains.finish(id, first, seed, 1)

    {:ok, _, _} = Trains.watch(id)

    assert Repo.all(from f in Follow, where: f.follower_id == ^creator.id, select: f.followed_id) ==
             [friend.id]
  end

  test "a process that joins a full game only watches", %{id: id} do
    {:ok, _, _} = Trains.join(id)

    assert {:ok, nil, %{players: [_]}} = Trains.join(id)
  end

  test "the state gives each decision with the player who made it", %{id: id} do
    {:ok, player_id, _} = Trains.join(id)

    Trains.decide(id, player_id, 0, [1, 1], [1, 2])

    assert {:ok, _,
            %{decisions: [%{train: 0, cell: [1, 1], exit: [1, 2], player_id: ^player_id}]}} =
             Trains.watch(id)
  end

  @tag players: 2, public: true
  test "a public game is open until it is full, then ongoing", %{id: id} do
    Lobby.subscribe(Game)
    {:ok, _, _} = Trains.join(id)
    assert_receive {:lobby_changed, Game, ^id, %{status: :open, seats_left: 1}}

    {:ok, _, _} = Trains.join(id)

    assert_receive {:lobby_changed, Game, ^id, %{status: :ongoing, players: [_, _]}}
  end

  describe "a match" do
    # Two players and a finished round
    setup %{id: id} do
      {:ok, first, _} = Trains.join(id)
      {:ok, second, %{seed: seed}} = Trains.join(id)
      Trains.finish(id, first, seed, 1)
      %{first: first, second: second}
    end

    @tag players: 2
    test "the other players cannot start a round while a player changes the settings",
         %{id: id, first: first, second: second} do
      {:ok, %{seed: seed, editing: ^first}} = Trains.edit_settings(id, first)

      Trains.restart(id, second)

      assert {:error, :not_allowed} = Trains.edit_settings(id, second)
      assert {:ok, nil, %{seed: ^seed, editing: ^first}} = Trains.watch(id)
    end

    @tag players: 2
    test "change_settings/3 starts a new round with the new settings",
         %{id: id, first: first} do
      {:ok, %{seed: seed}} = Trains.edit_settings(id, first)

      :ok =
        Trains.change_settings(id, first, %{switch_count: 8, trains_per_house: 3, pace: "hard"})

      assert {:ok, nil, state} = Trains.watch(id)

      assert %{editing: nil, switch_count: 8, trains_per_house: 3, pace: "hard", players: [_, _]} =
               state

      assert state.seed != seed
    end

    @tag players: 2
    test "the other players can play again when the page of the player closes",
         %{id: id, pid: pid, first: first} do
      task = Task.async(fn -> Trains.edit_settings(id, first) end)
      {:ok, %{editing: ^first}} = Task.await(task)
      ref = Process.monitor(task.pid)
      assert_receive {:DOWN, ^ref, :process, _, _}
      _ = :sys.get_state(pid)

      assert {:ok, nil, %{editing: nil}} = Trains.watch(id)
    end
  end
end
