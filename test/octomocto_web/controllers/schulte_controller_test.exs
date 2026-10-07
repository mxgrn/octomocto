defmodule OctomoctoWeb.SchulteControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /schulte shows the new game button", %{conn: conn} do
    conn = get(conn, ~p"/schulte")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#new-game") |> Enum.count() == 1
  end

  test "GET /schulte shows the leaderboards", %{conn: conn} do
    Octomocto.Schulte.save_results("a", %{"type" => "classic", "players" => 1}, 1000, [
      %{user_id: Octomocto.AccountsFixtures.user_fixture().id, score: 90}
    ])

    conn = get(conn, ~p"/schulte")

    document = LazyHTML.from_document(html_response(conn, 200))
    board = LazyHTML.query(document, "#leaderboard-classic-1")
    assert LazyHTML.query(board, ".latest-games li") |> Enum.count() == 1
    assert LazyHTML.query(board, ".best-results li") |> Enum.count() == 1
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
