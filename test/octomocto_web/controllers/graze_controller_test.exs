defmodule OctomoctoWeb.GrazeControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.Graze

  test "GET /graze/:id has the mount node for the game", %{conn: conn} do
    id = Graze.create_game(2, false)
    conn = get(conn, ~p"/graze/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#graze-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /graze/:id goes back to /graze for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/graze/unknown")

    assert redirected_to(conn) == ~p"/graze"
  end
end
