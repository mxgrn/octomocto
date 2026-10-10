defmodule OctomoctoWeb.SchulteControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.Schulte

  test "GET /schulte selects the classic board for one player", %{conn: conn} do
    conn = get(conn, ~p"/schulte")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#board-classic[aria-current]") |> Enum.count() == 1
    assert LazyHTML.query(document, "#players-1[aria-current]") |> Enum.count() == 1
    assert LazyHTML.query(document, "#new-game") |> Enum.count() == 1
  end

  test "GET /schulte shows the results of the selected settings only", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()

    Schulte.save_results("a", %{"type" => "random", "mode" => "easy", "players" => 2}, 1000, [
      %{user_id: user.id, score: 90}
    ])

    conn = get(conn, ~p"/schulte?board=random&players=2")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#latest-games li") |> LazyHTML.text() =~ "0:01.0"
    assert LazyHTML.query(document, "#best-results li") |> LazyHTML.text() =~ "0:01.0"
  end

  test "GET /schulte shows \"---\" in an empty list", %{conn: conn} do
    conn = get(conn, ~p"/schulte")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#latest-games li") |> LazyHTML.text() == "---"
    assert LazyHTML.query(document, "#best-results li") |> LazyHTML.text() == "---"
  end

  test "POST /schulte starts a game with the settings and opens its page", %{conn: conn} do
    conn = post(conn, ~p"/schulte?board=random&players=2")
    "/schulte/" <> id = redirected_to(conn)
    assert {:ok, _player_id, %{players_needed: 2}} = Schulte.join(id)

    conn = get(recycle(conn), ~p"/schulte/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#schulte-main[data-game-id='#{id}']") |> Enum.count() == 1
  end

  test "GET /schulte/:id goes back to /schulte for an unknown game", %{conn: conn} do
    conn = get(conn, ~p"/schulte/unknown")

    assert redirected_to(conn) == ~p"/schulte"
  end
end
