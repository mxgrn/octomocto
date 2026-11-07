defmodule OctomoctoWeb.StatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.NimbleMosaic

  test "shows a graph of the games per day of each game", %{conn: conn} do
    user = user_fixture()
    settings = %{"type" => "random", "mode" => "easy", "players" => 1}
    NimbleMosaic.save_results("a", settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(
             view,
             ~s|#stats-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end
end
