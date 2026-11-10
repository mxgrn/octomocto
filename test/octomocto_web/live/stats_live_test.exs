defmodule OctomoctoWeb.StatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Locales, NimbleMosaic}

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows a graph of the games per day of each game", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(
             view,
             ~s|#stats-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end

  test "gives the chart colors to the most played games first and repeats them after ten",
       %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, ~s|#legend-nimble-mosaic span[style$="var(--series-1)"]|)
    refute has_element?(view, ~s|#games-chart path[stroke="var(--series-11)"]|)
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

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(
             view,
             ~s|#stats-language-activity-pt[aria-label="1 game in the last 30 days"]|
           )
  end
end
