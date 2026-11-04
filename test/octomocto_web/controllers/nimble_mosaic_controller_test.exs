defmodule OctomoctoWeb.NimbleMosaicControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.NimbleMosaic

  test "GET /nimble-mosaic/:id has the mount node for the game", %{conn: conn} do
    id = NimbleMosaic.create_game(:random, :easy, 2, false)
    conn = get(conn, ~p"/nimble-mosaic/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#nimble-mosaic-main[data-game-id='#{id}']") |> Enum.count() ==
             1
  end

  test "GET /nimble-mosaic/:id goes back to /nimble-mosaic for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/nimble-mosaic/unknown")

    assert redirected_to(conn) == ~p"/nimble-mosaic"
  end
end
