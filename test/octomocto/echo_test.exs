defmodule Octomocto.EchoTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.{Echo, Lobby}
  alias Octomocto.Echo.{Game, Result, Store}

  # One player and a private game, if the test has no `@tag players: n` or
  # `@tag public: true`
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"
    config = [players: tags[:players] || 1, public: tags[:public] || false]
    pid = start_supervised!(echo_game(id, config))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id, pid: pid}
  end

  defp watch(id) do
    {:ok, nil, state} = Echo.watch(id)
    state
  end

  defp wrong(pad), do: rem(pad + 1, 4)

  describe "alone" do
    test "start adds a random pad, and repeating the sequence adds one more", %{id: id} do
      {:ok, player_id, %{waiting: false, turn: player_id}} = Echo.join(id)

      Echo.start(id, player_id)
      assert %{sequence: [pad], length: 1} = watch(id)

      Echo.press(id, player_id, pad)
      assert %{sequence: [^pad, _], players: [%{score: 1}]} = watch(id)
    end

    test "a wrong pad ends the game and saves the result", %{id: id} do
      {:ok, player_id, _} = Echo.join(id)
      Echo.start(id, player_id)
      %{sequence: [pad]} = watch(id)

      Echo.press(id, player_id, wrong(pad))

      assert %{finished: true, players: [%{out: 1}]} = watch(id)
      assert [%Result{score: 0, settings: %{"pads" => 4, "players" => 1}}] = Repo.all(Result)
    end

    test "restart starts the first round at once, with zero scores", %{id: id} do
      {:ok, player_id, _} = Echo.join(id)
      Echo.start(id, player_id)
      %{sequence: [pad]} = watch(id)
      Echo.press(id, player_id, pad)

      Echo.restart(id, player_id)

      assert %{length: 1, finished: false, players: [%{score: 0, out: nil}]} = watch(id)
    end

    test "a game starts again from its copy in the store when its process stops",
         %{id: id, pid: pid} do
      {:ok, player_id, _} = Echo.join(id)
      Echo.start(id, player_id)
      %{sequence: sequence} = watch(id)

      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      # The name of the game is free only after :global sees the exit
      _ = :sys.get_state(:global_name_server)

      assert %{sequence: ^sequence} = watch(id)
    end
  end

  describe "with 2 or more players" do
    @tag players: 2
    test "the game is ready when it is full, and the first player only adds a pad",
         %{id: id} do
      {:ok, first, %{waiting: true}} = Echo.join(id)
      {:ok, second, _} = Echo.join(id)

      assert %{waiting: false, turn: ^first, turn_limit_ms: 15_000} = watch(id)

      Echo.press(id, second, 0)
      Echo.press(id, first, 2)

      assert %{length: 1, turn: ^second, sequence: nil} = watch(id)
    end

    @tag players: 2
    test "a wrong pad puts the player out, and the last player in wins and the game is saved",
         %{id: id} do
      {:ok, first, _} = Echo.join(id)
      {:ok, second, _} = Echo.join(id)
      Echo.press(id, first, 2)

      Echo.press(id, second, wrong(2))

      assert %{finished: true, winner: ^first} = watch(id)
      assert [%Result{}, %Result{}] = Repo.all(Result)
    end

    @tag players: 2
    test "the turn goes to the next player when the turn timer runs out", %{id: id, pid: pid} do
      {:ok, _first, _} = Echo.join(id)
      {:ok, second, _} = Echo.join(id)

      send(pid, {:turn_timeout, Store.read(id).turn_ref})

      assert %{turn: ^second} = watch(id)
    end

    @tag players: 2
    test "a timer of an older turn does not count", %{id: id, pid: pid} do
      {:ok, first, _} = Echo.join(id)
      {:ok, _second, _} = Echo.join(id)

      send(pid, {:turn_timeout, make_ref()})

      assert %{turn: ^first} = watch(id)
    end

    @tag players: 2
    test "when the player of the turn leaves, the other player wins", %{id: id} do
      test = self()

      task =
        Task.async(fn ->
          {:ok, player_id, _} = Echo.join(id)
          send(test, :joined)
          receive do: (:leave -> player_id)
        end)

      assert_receive :joined
      {:ok, second, _} = Echo.join(id)
      send(task.pid, :leave)
      Task.await(task)

      assert_receive {:echo_state, %{finished: true, winner: ^second, turn: ^second}}
      assert %{players: [%{id: ^second}]} = watch(id)
      assert Repo.all(Result) == []
    end

    @tag players: 3
    test "when the player of the turn leaves a game of 3, the turn goes to the next player",
         %{id: id} do
      test = self()

      task =
        Task.async(fn ->
          {:ok, player_id, _} = Echo.join(id)
          send(test, :joined)
          receive do: (:leave -> player_id)
        end)

      assert_receive :joined
      {:ok, second, _} = Echo.join(id)
      {:ok, _third, _} = Echo.join(id)
      send(task.pid, :leave)
      Task.await(task)

      assert_receive {:echo_state, %{turn: ^second, finished: false, players: [_, _]}}
    end

    @tag players: 2
    test "a process that joins a full game only watches", %{id: id} do
      {:ok, _, _} = Echo.join(id)
      {:ok, _, _} = Echo.join(id)

      assert {:ok, nil, %{players: [_, _]}} = Echo.join(id)
    end
  end

  describe "lobby" do
    setup do
      Lobby.subscribe(Game)
    end

    @tag players: 2, public: true
    test "a public game is open until it is full, then ongoing, and the rows show the turn",
         %{id: id} do
      {:ok, _, _} = Echo.join(id)

      assert_receive {:lobby_changed, Game, ^id,
                      %{
                        status: :open,
                        seats_left: 1,
                        settings: %{pads: 4},
                        players: [%{turn: true}]
                      }}

      {:ok, _, _} = Echo.join(id)

      assert_receive {:lobby_changed, Game, ^id,
                      %{
                        status: :ongoing,
                        finished: false,
                        players: [%{turn: true}, %{turn: false}]
                      }}
    end
  end
end
