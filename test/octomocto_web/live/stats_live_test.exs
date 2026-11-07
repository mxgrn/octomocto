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
