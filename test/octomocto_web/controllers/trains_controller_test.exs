defmodule OctomoctoWeb.TrainsControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /trains has the mount node for the game", %{conn: conn} do
    conn = get(conn, ~p"/trains")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#trains-main") |> Enum.count() == 1
  end
end
