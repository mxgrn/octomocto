defmodule OctomoctoWeb.PageControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Peace of mind from prototype to production"
  end

  test "GET /elm renders the Elm mount node", %{conn: conn} do
    conn = get(conn, ~p"/elm")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#elm-main") |> Enum.count() == 1
  end

  test "GET /penguin renders the penguin maze mount node", %{conn: conn} do
    conn = get(conn, ~p"/penguin")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#penguin-main") |> Enum.count() == 1
  end
end
