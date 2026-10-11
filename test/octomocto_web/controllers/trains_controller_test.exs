defmodule OctomoctoWeb.TrainsControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.Trains

  test "GET /trains/:id has the mount node for the game", %{conn: conn} do
    id = Trains.create_game(%{players: 1, switch_count: 12, trains_per_house: 2, pace: "normal"})
    conn = get(conn, ~p"/trains/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#trains-main") |> LazyHTML.attribute("data-game-id") == [id]
  end
end
