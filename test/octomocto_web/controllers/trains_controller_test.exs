defmodule OctomoctoWeb.TrainsControllerTest do
  use OctomoctoWeb.ConnCase

  alias Octomocto.Trains

  test "GET /trains/:id has the mount node for the game", %{conn: conn} do
    id =
      Trains.create_game(%{
        players: 1,
        switch_count: 12,
        trains_per_house: 2,
        pace: "normal",
        public: false
      })

    conn = get(conn, ~p"/trains/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    assert LazyHTML.query(document, "#trains-main") |> LazyHTML.attribute("data-game-id") == [id]
  end

  test "GET /pt/trains/:id gives the texts in Portuguese to the game", %{conn: conn} do
    id =
      Trains.create_game(%{
        players: 1,
        switch_count: 4,
        trains_per_house: 1,
        pace: "easy",
        public: false
      })

    conn = get(conn, "/pt/trains/#{id}")

    document = LazyHTML.from_document(html_response(conn, 200))
    main = LazyHTML.query(document, "#trains-main")
    assert LazyHTML.attribute(main, "data-locale") == ["pt"]
    assert ["/pt/trains?" <> _] = LazyHTML.attribute(main, "data-settings-url")
    [texts] = LazyHTML.attribute(main, "data-texts")
    assert Jason.decode!(texts)["Play again"] == "Jogar de novo"
  end
end
