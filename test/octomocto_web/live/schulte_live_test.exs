defmodule OctomoctoWeb.SchulteLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Schulte

  test "selects the classic board for one player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    assert has_element?(view, "#board-classic[aria-current]")
    assert has_element?(view, "#players-1[aria-current]")
    assert has_element?(view, "#new-game")
  end

  test "changes a setting without a page load", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    view |> element("#players-2") |> render_click()

    assert_patch(view, ~p"/schulte?board=classic&mode=easy&players=2")
    assert has_element?(view, "#players-2[aria-current]")
  end

  test "shows the results of the selected settings only", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()

    Schulte.save_results("a", %{"type" => "random", "mode" => "easy", "players" => 2}, 1000, [
      %{user_id: user.id, score: 90}
    ])

    {:ok, view, _html} = live(conn, ~p"/schulte?board=random&players=2")

    assert view |> element("#latest-games li") |> render() =~ "0:01.0"
    assert view |> element("#best-results li") |> render() =~ "0:01.0"
  end

  test "shows an empty-state text in an empty list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    assert view |> element("#latest-games li") |> render() =~ "No games yet — be the first."
    assert view |> element("#best-results li") |> render() =~ "No games yet — be the first."
  end

  test "new game starts a game with the settings and opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte?board=random&players=2")

    {:error, {:redirect, %{to: "/schulte/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{players_needed: 2}} = Schulte.join(id)
  end
end
