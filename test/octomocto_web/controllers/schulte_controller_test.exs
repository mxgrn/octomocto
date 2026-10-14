defmodule OctomoctoWeb.SchulteControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.Schulte

  test "GET /schulte/:id has the mount node for the game", %{conn: conn} do
    id = Schulte.create_game(:random, :easy, 2, false)
    conn = get(conn, ~p"/schulte/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#schulte-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /schulte/:id goes back to /schulte for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/schulte/unknown")

    assert redirected_to(conn) == ~p"/schulte"
  end
end
