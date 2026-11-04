defmodule OctomoctoWeb.LanguageStatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Locales, Repo, Schulte}
  alias Octomocto.Schulte.Result

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows the games of players of the language, with links to the game stats", %{conn: conn} do
    portuguese = user_fixture()
    german = user_fixture()
    Locales.put(portuguese.id, nil, "pt-BR")
    Locales.put(german.id, nil, "de-DE")

    Schulte.save_results("a", @settings, 1000, [%{user_id: portuguese.id, score: 90}])
    Schulte.save_results("b", @settings, 1000, [%{user_id: german.id, score: 90}])
    Schulte.save_results("c", @settings, 1000, [%{user_id: german.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, ~s|#language-game-schulte a[href="/stats/schulte"]|)
    assert view |> element("#language-game-schulte .tabular-nums") |> render() =~ ~r/>\s*1\s*</
  end

  test "does not count the games from before the last 30 days", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    Schulte.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Repo.update_all(Result, set: [inserted_at: DateTime.add(DateTime.utc_now(), -30, :day)])

    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, "#language-games-empty")
  end

  test "shows an empty list for a language without games", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats/languages/pt")

    assert has_element?(view, "#language-games-empty")
  end

  test "the stats page links each language to its stats page", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    Schulte.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, ~s|#stats-language-pt a[href="/stats/languages/pt"]|)
  end
end
