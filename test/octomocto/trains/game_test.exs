defmodule Octomocto.Trains.GameTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.{Lobby, Trains}
  alias Octomocto.Trains.Game

  # One player and a private game, if the test has no `@tag players: n` or
  # `@tag public: true`
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"

    config =
      [players: tags[:players] || 1, public: tags[:public] || false] ++ (tags[:config] || [])

    pid = start_supervised!(trains_game(id, config))
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

  test "a process that joins a full game only watches", %{id: id} do
    {:ok, _, _} = Trains.join(id)

    assert {:ok, nil, %{players: [_]}} = Trains.join(id)
  end

  @tag players: 2, public: true
  test "a public game is open until it is full, then ongoing", %{id: id} do
    Lobby.subscribe(Game)
    {:ok, _, _} = Trains.join(id)
    assert_receive {:lobby_changed, Game, ^id, %{status: :open, seats_left: 1}}

    {:ok, _, _} = Trains.join(id)

    assert_receive {:lobby_changed, Game, ^id, %{status: :ongoing, players: [_, _]}}
  end
end
