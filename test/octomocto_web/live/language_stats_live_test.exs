defmodule OctomoctoWeb.LanguageStatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Locales, Repo, NimbleMosaic}
  alias Octomocto.NimbleMosaic.Result

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows the games of players of the language, with links to the game stats", %{conn: conn} do
    portuguese = user_fixture()
    german = user_fixture()
    Locales.put(portuguese.id, nil, "pt-BR")
    Locales.put(german.id, nil, "de-DE")

    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: portuguese.id, score: 90}])
    NimbleMosaic.save_results("b", @settings, 1000, [%{user_id: german.id, score: 90}])
    NimbleMosaic.save_results("c", @settings, 1000, [%{user_id: german.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt?today=1")

    assert has_element?(
             view,
             ~s|#language-game-nimble-mosaic a[href="/stats/nimble-mosaic?today=1"]|
           )

    assert view |> element("#language-game-nimble-mosaic .tabular-nums") |> render() =~
             ~r/>\s*1\s*</

    assert has_element?(
             view,
             ~s|#language-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end

  test "does not count the games from before the 30 days before today", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Repo.update_all(Result, set: [inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)])

    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, "#language-games-empty")
  end

  test "does not count the games of today until the toggle includes them", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, "#language-games-empty")

    view |> element("#include-today") |> render_click()

    assert_patch(view, ~p"/stats/languages/pt?today=1")
    assert has_element?(view, "#language-game-nimble-mosaic")
  end

  test "shows an empty list for a language without games", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, "#language-games-empty")
  end

  test "the stats page links each language to its stats page", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats?today=1")

    assert has_element?(view, ~s|#stats-language-pt a[href="/stats/languages/pt?today=1"]|)
  end
end
