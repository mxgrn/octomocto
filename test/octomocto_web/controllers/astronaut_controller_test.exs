defmodule OctomoctoWeb.AstronautControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /astronaut shows the new game button", %{conn: conn} do
    conn = get(conn, ~p"/astronaut")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#new-game") |> Enum.count() == 1
  end

  test "POST /astronaut starts a game and opens its page", %{conn: conn} do
    conn = post(conn, ~p"/astronaut")
    "/astronaut/" <> id = redirected_to(conn)

    conn = get(recycle(conn), ~p"/astronaut/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#astronaut-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /astronaut/:id goes back to /astronaut for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/astronaut/unknown")

    assert redirected_to(conn) == ~p"/astronaut"
  end
end
