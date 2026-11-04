defmodule OctomoctoWeb.NimbleMosaicLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.NimbleMosaic
  alias OctomoctoWeb.NimbleMosaicLive

  test "the next game of a match has no creator" do
    id = NimbleMosaicLive.create_default_game(2, false)
    pid = GenServer.whereis(NimbleMosaic.Game.via(id))
    on_exit(fn -> DynamicSupervisor.terminate_child(NimbleMosaic.GameSupervisor, pid) end)

    {:ok, _player_id, _state} = NimbleMosaic.join(id)

    assert %{creator: false} = NimbleMosaic.Store.read(id)
  end

  test "selects the classic board for one player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic")

    assert has_element?(view, "#board-classic[aria-current]")
    assert has_element?(view, "#players-1[aria-current]")
    assert has_element?(view, "#new-game")
  end

  test "changes a setting without a page load", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic")

    view |> element("#players-2") |> render_click()

    assert_patch(view, ~p"/nimble-mosaic?board=classic&mode=easy&players=2")
    assert has_element?(view, "#players-2[aria-current]")
  end

  test "shows the results of the selected settings only", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()

    NimbleMosaic.save_results(
      "a",
      %{"type" => "random", "mode" => "easy", "players" => 2},
      1000,
      [
        %{user_id: user.id, score: 90}
      ]
    )

    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic?board=random&players=2")

    assert view |> element("#best-results li") |> render() =~ "0:01.0"
  end

  test "shows an empty-state text in an empty list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic")

    assert view |> element("#best-results li") |> render() =~ "No games yet — be the first."
  end

  test "new game starts a game with the settings and opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic?board=random&players=2")

    {:error, {:redirect, %{to: "/nimble-mosaic/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{players_needed: 2}} = NimbleMosaic.join(id)
  end
end
