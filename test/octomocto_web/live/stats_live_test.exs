defmodule OctomoctoWeb.StatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Locales, NimbleMosaic, Repo}
  alias Octomocto.NimbleMosaic.Result

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows a graph of the games per day of each game", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats?today=1")

    assert has_element?(
             view,
             ~s|#stats-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end

  test "gives the chart colors to the most played games first and repeats them after ten",
       %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats?today=1")

    assert has_element?(view, ~s|#legend-nimble-mosaic span[style$="var(--series-1)"]|)
    refute has_element?(view, ~s|#games-chart path[stroke="var(--series-11)"]|)
  end

  test "does not count the games of today until the toggle includes them", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(
             view,
             ~s|#stats-activity-nimble-mosaic[aria-label="0 games in the last 30 days"]|
           )

    view |> element("#include-today") |> render_click()

    assert_patch(view, ~p"/stats?today=1")
    assert has_element?(view, ~s|#include-today[aria-checked="true"]|)

    assert has_element?(
             view,
             ~s|#stats-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end

  test "counts the games of the 30 days before today", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Repo.update_all(Result, set: [inserted_at: DateTime.add(DateTime.utc_now(), -30, :day)])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert view |> element("#games-total") |> render() =~ ~r/>\s*1\s*</
  end

  test "counts only the games of the 7 days before today on the 7-day tab", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Repo.update_all(Result, set: [inserted_at: DateTime.add(DateTime.utc_now(), -8, :day)])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, ~s|#days-30[aria-current="page"]|)
    assert view |> element("#games-total") |> render() =~ ~r/>\s*1\s*</

    view |> element("#days-7") |> render_click()

    assert_patch(view, ~p"/stats?days=7")
    assert has_element?(view, ~s|#days-7[aria-current="page"]|)
    assert view |> element("#games-total") |> render() =~ ~r/>\s*0\s*</
  end

  test "shows 30 days for an unknown number of days", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats?days=5")

    assert has_element?(view, ~s|#days-30[aria-current="page"]|)
    assert has_element?(view, ~s|#stats-activity-memory[aria-label$="in the last 30 days"]|)
  end

  test "keeps the number of days and the toggle together", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats?days=7")

    view |> element("#include-today") |> render_click()

    assert_patch(view, ~p"/stats?days=7&today=1")
    assert has_element?(view, ~s|#days-30[href="/stats?today=1"]|)
    assert has_element?(view, ~s|#stats-memory a[href="/stats/memory?days=7&today=1"]|)
    assert has_element?(view, ~s|#stats-activity-memory[aria-label$="in the last 7 days"]|)
  end

  test "always shows the games of today in the Today number", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert view |> element("#games-today") |> render() =~ ~r/>\s*1\s*</
  end

  test "keeps the toggle in the links to the game stats pages", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats?today=1")

    assert has_element?(view, ~s|#stats-memory a[href="/stats/memory?today=1"]|)
  end

  test "shows a total line in the chart that a click on its legend hides", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, ~s|#games-chart path[data-series="total"]|)

    view |> element("#legend-total") |> render_click()

    refute has_element?(view, ~s|#games-chart path[data-series="total"]|)
    assert has_element?(view, ~s|#legend-total[aria-pressed="false"]|)
  end

  test "shows a graph of the games per day of each language", %{conn: conn} do
    user = user_fixture()
    Locales.put(user.id, nil, "pt-BR")
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats?today=1")

    assert has_element?(
             view,
             ~s|#stats-language-activity-pt[aria-label="1 game in the last 30 days"]|
           )
  end
end
