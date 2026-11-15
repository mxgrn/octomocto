defmodule OctomoctoWeb.VisitorsTest do
  # Not async: the visitors of all tests are in the same count
  use OctomoctoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Octomocto.Visitors

  test "the footer of a LiveView page counts a new visitor live", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats")
    count = Visitors.count()
    Visitors.subscribe()

    Visitors.track(self(), Visitors.key(nil, Ecto.UUID.generate()))

    # The page gets the same message
    assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 2000
    assert has_element?(view, "#online-count-#{count + 1}")
  end

  test "two pages of the same guest count as one visitor", %{conn: conn} do
    conn = init_test_session(conn, %{"guest_id" => Ecto.UUID.generate()})
    count = Visitors.count()

    {:ok, _first, _html} = live(conn, ~p"/stats")
    {:ok, _second, _html} = live(conn, ~p"/stats")

    assert Visitors.count() == count + 1
  end

  test "the footer of a controller page shows the count", %{conn: conn} do
    conn = get(conn, ~p"/privacy")

    document = LazyHTML.from_document(html_response(conn, 200))
    refute Enum.empty?(LazyHTML.query(document, "#online-count"))
  end
end
