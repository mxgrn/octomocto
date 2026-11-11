defmodule Octomocto.GrazeTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers
  import Octomocto.AccountsFixtures

  alias Octomocto.Graze
  alias Octomocto.Graze.{Game, Result}

  # A square that stays at `x`, `y`
  defp square(kind, x, y) do
    now = System.system_time(:millisecond)

    %{
      id: -1,
      kind: kind,
      size: 28,
      x: x,
      y: y,
      vx: 0.0,
      vy: 0.0,
      t: now - 1000,
      until: now + 60_000
    }
  end

  # One player, if the test has no `@tag config: [...]`. The field runs
  # when the test starts.
  setup tags do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(graze_game(id, tags[:config] || []))

    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(id))
    %{id: id, pid: pid}
  end

  # Joins and waits until the circle is placed and the first food comes
  defp join_and_start(id, user_id \\ nil) do
    {:ok, player_id, _state} = Graze.join(id, user_id)
    assert_receive {:graze_state, %{squares: [_ | _]}}, 1000
    player_id
  end

  # Puts the square into the field
  defp put_square(pid, square) do
    :sys.replace_state(pid, fn {game, state} -> {game, %{state | squares: [square]}} end)
  end

  test "a solo circle starts in the center with full energy", %{id: id} do
    {:ok, player_id, _state} = Graze.join(id)

    assert_receive {:graze_state, %{circles: [circle]}}, 1000
    assert %{id: ^player_id, x: 500.0, y: 500.0, alive: true, energy: 1.0} = circle
  end

  test "a circle that touches a food square eats it", %{id: id, pid: pid} do
    player_id = join_and_start(id)
    put_square(pid, square(:food, 560, 500))

    Graze.steer(id, player_id, 560, 500, System.system_time(:millisecond))

    assert_receive {:graze_state, %{players: [%{score: 1}]} = state}, 1000
    refute Enum.any?(state.squares, &(&1.id == -1))
  end

  test "a perk square gives a point and makes the circle invisible", %{id: id, pid: pid} do
    player_id = join_and_start(id)
    put_square(pid, Map.put(square(:food, 560, 500), :perk, :invisible))

    t = System.system_time(:millisecond)
    Graze.steer(id, player_id, 560, 500, t)

    assert_receive {:graze_state, %{players: [%{score: 1}], circles: [circle]}}, 1000
    assert circle.invisible_until > t + 9000

    # No new perk square comes for half of the perk time
    {_game, state} = :sys.get_state(pid)
    assert state.perk_paused_until > t + 4000
  end

  test "an invisible circle goes through a danger square until the perk ends",
       %{id: id, pid: pid} do
    player_id = join_and_start(id)
    now = System.system_time(:millisecond)

    :sys.replace_state(pid, fn {game, state} ->
      state = put_in(state.players[player_id].invisible_until, now + 500)
      {game, %{state | squares: [square(:danger, 500, 500)]}}
    end)

    # The circle is in the danger square, and still in the field
    assert_receive {:graze_state, %{circles: [%{alive: true}], squares: [%{id: -1} | _]}}, 1000
    assert_receive {:graze_state, %{circles: [%{alive: false}]}}, 1500
  end

  test "a danger square ends the field and saves the result", %{id: id, pid: pid} do
    user = user_fixture()
    player_id = join_and_start(id, user.id)
    put_square(pid, square(:danger, 560, 500))

    Graze.steer(id, player_id, 560, 500, System.system_time(:millisecond))

    assert_receive {:graze_state, %{finished: true, circles: [%{alive: false}]}}, 1000
    assert [%Result{score: 0, settings: %{"players" => 1}} = result] = Repo.all(Result)
    assert result.user_id == user.id
    assert result.elapsed_ms > 0
  end

  test "there are as many food squares as danger squares", %{id: id, pid: pid} do
    join_and_start(id)

    dangers =
      for {x, y} <- [{50, 50}, {950, 50}, {50, 950}, {950, 950}, {50, 500}] do
        %{square(:danger, x, y) | id: x * 1000 + y}
      end

    :sys.replace_state(pid, fn {game, state} -> {game, %{state | squares: dangers}} end)

    # The first state after the change starts with the danger squares
    assert_receive {:graze_state, %{squares: [%{id: 50_050} | _] = squares}}, 1000
    assert Enum.count(squares, &(&1.kind == :food)) == 5
  end

  test "best_results/1 gives the highest score first" do
    [first, second] = for _ <- 1..2, do: user_fixture()
    settings = %{"players" => 1}

    Graze.save_results("a", settings, 0, [%{user_id: first.id, score: 4, survived_ms: 9000}])
    Graze.save_results("b", settings, 0, [%{user_id: second.id, score: 7, survived_ms: 5000}])

    assert [%Result{score: 7}, %Result{score: 4}] = Graze.best_results(settings)
  end
end
