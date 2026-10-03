defmodule OctomoctoWeb.PenguinControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /penguin shows the new game button", %{conn: conn} do
    conn = get(conn, ~p"/penguin")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#new-game") |> Enum.count() == 1
  end

  test "POST /penguin starts a game and opens its page", %{conn: conn} do
    conn = post(conn, ~p"/penguin")
    "/penguin/" <> id = redirected_to(conn)

    conn = get(recycle(conn), ~p"/penguin/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#penguin-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /penguin/:id goes back to /penguin for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/penguin/unknown")

    assert redirected_to(conn) == ~p"/penguin"
  end
end
