defmodule OctomoctoWeb.GrazeLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Graze

  test "selects one player without perks in a public game", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/graze")

    assert has_element?(view, "#players-1[aria-current]")
    assert has_element?(view, "#perks-off[aria-current]")
    assert has_element?(view, "#visibility-public[aria-current]")
  end

  test "shows the best score of the selected settings", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()
    settings = %{"players" => 2, "perks" => true}

    Graze.save_results("a", settings, 0, [%{user_id: user.id, score: 17, survived_ms: 1}])

    {:ok, view, _html} = live(conn, ~p"/graze?players=2&perks=on")
    assert view |> element("#best-results li") |> render() =~ "17"

    {:ok, view, _html} = live(conn, ~p"/graze?players=2&perks=off")
    refute has_element?(view, "#best-results li", "17")
  end

  test "new game starts a game with the settings and opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/graze?players=3&perks=on")

    {:error, {:redirect, %{to: "/graze/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{players_needed: 3}} = Graze.join(id)
    assert %{perks: true} = Octomocto.Graze.Store.read(id)
  end
end
