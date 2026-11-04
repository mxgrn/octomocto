defmodule Octomocto.Memory.GameTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers
  import Octomocto.AccountsFixtures

  alias Octomocto.{Lobby, Memory}
  alias Octomocto.Friends.Follow
  alias Octomocto.Memory.Game

  test "lobby_entry/1 gives no bombs for a stored state from before the bombs" do
    player = %{name: "Zippy Sponge", color_name: "lime", left: nil, joined_at: 1, score: 0}

    state = %{
      id: "game",
      public: true,
      listed: true,
      ready: false,
      needed: 2,
      created_at: 1,
      campaign: nil,
      theme: "monsters",
      set: 2,
      size: 60,
      turn: "player",
      players: %{"player" => player}
    }

    assert %{settings: %{bombs: 0}} = Game.lobby_entry(state)
  end

  describe "players" do
    # One player and a private game, if the test has no `@tag players: n`
    # or `@tag public: true`
    setup tags do
      id = "game-#{System.unique_integer([:positive])}"

      config =
        [players: tags[:players] || 1, public: tags[:public] || false] ++ (tags[:config] || [])

      pid = start_supervised!(memory_game(id, config))
      Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
      Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
      %{id: id, pid: pid}
    end

    test "join/5 with the id of a player gives the same player back", %{id: id} do
      {:ok, player_id, _} = Memory.join(id)

      assert {:ok, ^player_id, %{players: [%{id: ^player_id}]}} =
               Memory.join(id, nil, nil, player_id)
    end

    @tag config: [rejoin_grace_ms: :timer.minutes(1)]
    test "a player can join again after its process stops", %{id: id, pid: pid} do
      task = Task.async(fn -> Memory.join(id) end)
      {:ok, player_id, _} = Task.await(task)
      ref = Process.monitor(task.pid)
      assert_receive {:DOWN, ^ref, :process, _, _}
      _ = :sys.get_state(pid)

      assert {:ok, ^player_id, %{players: [%{id: ^player_id}]}} =
               Memory.join(id, nil, nil, player_id)
    end

    @tag players: 2
    test "the players have different colors", %{id: id} do
      {:ok, _, _} = Memory.join(id)
      {:ok, _, %{players: [first, second]}} = Memory.join(id)

      assert first.color != second.color
    end

    @tag players: 2
    test "a player is removed after the process of the player stops", %{id: id} do
      {:ok, first, _} = Memory.join(id)
      assert_receive {:memory_state, %{players: [_]}}

      Task.async(fn -> Memory.join(id) end) |> Task.await()

      assert_receive {:memory_state, %{players: [_, _]}}
      assert_receive {:memory_state, %{players: [%{id: ^first}]}}
    end

    @tag players: 2
    test "a finished field makes friends of the creator and a player from a shared link",
         %{id: id, pid: pid} do
      [creator, friend] = for _ <- 1..2, do: user_fixture()
      {:ok, first, _} = Memory.join(id, creator.id)
      {:ok, _, _} = Memory.join(id, friend.id)

      # The first player turns all pairs, so the turn does not change
      %{cards: cards} = :sys.get_state(pid)

      for {_image, pair} <- cards |> Enum.with_index() |> Enum.group_by(&elem(&1, 0).image),
          {_card, i} <- pair,
          do: Memory.flip(id, first, i)

      assert {:ok, nil, %{finished: true}} = Memory.watch(id)

      assert Repo.all(
               from f in Follow, where: f.follower_id == ^creator.id, select: f.followed_id
             ) ==
               [friend.id]
    end

    test "a process that joins a full game only watches", %{id: id} do
      {:ok, _, _} = Memory.join(id)

      assert {:ok, nil, %{players: [_]}} = Memory.join(id)
    end

    @tag players: 2, public: true
    test "a public game is open until it is full, then ongoing", %{id: id} do
      Lobby.subscribe(Game)
      {:ok, _, _} = Memory.join(id)
      assert_receive {:lobby_changed, Game, ^id, %{status: :open, seats_left: 1}}

      {:ok, _, _} = Memory.join(id)

      assert_receive {:lobby_changed, Game, ^id,
                      %{status: :ongoing, players: [%{turn: true}, %{turn: false}]}}
    end
  end
end
