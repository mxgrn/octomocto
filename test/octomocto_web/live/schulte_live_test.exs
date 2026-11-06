defmodule OctomoctoWeb.SchulteLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Schulte

  @settings %{"size" => 5, "marks" => false, "players" => 1}

  test "selects a 5 × 5 grid without marks for one player", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    assert has_element?(view, "#size-5[aria-current]")
    assert has_element?(view, "#marks-off[aria-current]")
    assert has_element?(view, "#players-1[aria-current]")
  end

  test "changes a setting without a page load", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    view |> element("#size-7") |> render_click()

    assert_patch(view, ~p"/schulte?marks=off&players=1&size=7")
    assert has_element?(view, "#size-7[aria-current]")
  end

  test "shows the results of the selected settings only", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()
    settings = %{"size" => 6, "marks" => true, "players" => 1}
    Schulte.save_results("a", settings, 1000, [%{user_id: user.id, score: 36}])

    {:ok, view, _html} = live(conn, ~p"/schulte?size=6&marks=on")
    assert view |> element("#best-results li") |> render() =~ "0:01.0"

    {:ok, view, _html} = live(conn, ~p"/schulte?size=6")
    refute view |> element("#best-results li") |> render() =~ "0:01.0"
  end

  test "new game starts a game with the settings and opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte?size=8&marks=on&players=2")

    {:error, {:redirect, %{to: "/schulte/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{size: 8, marks: true, players_needed: 2}} = Schulte.join(id)
  end

  describe "best results filter" do
    setup :register_and_log_in_user

    test "shows only the user and the followed players", %{conn: conn, user: user} do
      [followed, stranger] = for _ <- 1..2, do: Octomocto.AccountsFixtures.user_fixture()
      Octomocto.Friends.follow(user.id, followed.id)

      for player <- [user, followed, stranger] do
        Schulte.save_results("a", @settings, 1000, [%{user_id: player.id, score: 25}])
      end

      {:ok, view, _html} = live(conn, ~p"/schulte")
      view |> element("#best-results-following") |> render_click()

      assert has_element?(view, ~s|#best-results a[href="/players/#{user.public_id}"]|)
      assert has_element?(view, ~s|#best-results a[href="/players/#{followed.public_id}"]|)
      refute has_element?(view, ~s|#best-results a[href="/players/#{stranger.public_id}"]|)
    end

    test "keeps the filter when a setting changes", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/schulte")
      view |> element("#best-results-following") |> render_click()

      view |> element("#size-7") |> render_click()

      assert has_element?(view, ~s|#best-results-following[aria-pressed="true"]|)
    end
  end

  test "has no best results filter for a guest", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/schulte")

    refute has_element?(view, "#best-results-filter")
  end
end
