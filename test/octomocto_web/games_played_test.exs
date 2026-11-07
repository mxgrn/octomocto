defmodule OctomoctoWeb.GamesPlayedTest do
  # Not async: the finished games go to all pages of all tests
  use OctomoctoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Octomocto.Stats

  test "the footer of a LiveView page counts the finished games live", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats")
    count = Stats.Counter.get()

    Stats.broadcast_game_finished()

    assert has_element?(view, "#games-played-count-#{count + 1}")
  end

  test "the footer of a controller page shows the count", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    count = Stats.Counter.get()
    document = LazyHTML.from_document(html_response(conn, 200))
    refute Enum.empty?(LazyHTML.query(document, "#games-played-count-#{count}"))
  end
end
