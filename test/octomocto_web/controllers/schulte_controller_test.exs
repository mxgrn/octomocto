defmodule OctomoctoWeb.SchulteControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /schulte shows the new game button", %{conn: conn} do
    conn = get(conn, ~p"/schulte")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#new-game") |> Enum.count() == 1
  end

  test "POST /schulte starts a game and opens its page", %{conn: conn} do
    conn = post(conn, ~p"/schulte")
    "/schulte/" <> id = redirected_to(conn)

    conn = get(recycle(conn), ~p"/schulte/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#schulte-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /schulte/:id goes back to /schulte for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/schulte/unknown")

    assert redirected_to(conn) == ~p"/schulte"
  end
end
