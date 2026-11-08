defmodule OctomoctoWeb.PageControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET / links to all games", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    hrefs =
      document
      |> LazyHTML.query("#games a")
      |> LazyHTML.attribute("href")

    assert hrefs == [
             "/nimble-mosaic",
             "/schulte",
             "/graze",
             "/trains",
             "/memory",
             "/set",
             "/sudoku",
             "/echo",
             "/mahjong",
             "/overlap",
             "/snap",
             "/afterglow"
           ]
  end

  test "GET / marks only the single-player games", %{conn: conn} do
    conn = get(conn, ~p"/")

    ids =
      LazyHTML.from_document(html_response(conn, 200))
      |> LazyHTML.query("#games [id^=game-single-player-]")
      |> LazyHTML.attribute("id")

    assert ids == ["game-single-player-snap"]
  end

  test "the header shows the slogan", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#site-header #slogan") |> LazyHTML.text() =~ "Use your heads"
  end

  test "the header has the theme selector", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    themes =
      document
      |> LazyHTML.query("#theme-toggle button")
      |> LazyHTML.attribute("data-phx-theme")

    assert themes == ["system", "light", "dark"]
  end

  test "game pages link back home", %{conn: conn} do
    conn = get(conn, ~p"/trains")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#home-link") |> LazyHTML.attribute("href") == ["/"]
  end

  test "the header wordmark is larger on the home page", %{conn: conn} do
    home = LazyHTML.from_document(html_response(get(conn, ~p"/"), 200))
    game = LazyHTML.from_document(html_response(get(conn, ~p"/trains"), 200))

    assert LazyHTML.query(home, "#home-link svg.sm\\:h-\\[1\\.8rem\\]") |> Enum.count() == 1
    assert LazyHTML.query(game, "#home-link svg.h-6") |> Enum.count() == 1
  end

  test "game pages use the full width", %{conn: conn} do
    id =
      Octomocto.Trains.create_game(%{
        players: 1,
        switch_count: 12,
        trains_per_house: 2,
        pace: "normal",
        public: false
      })

    game = LazyHTML.from_document(html_response(get(conn, ~p"/trains/#{id}"), 200))

    assert LazyHTML.query(game, "main > .max-w-2xl") |> Enum.count() == 0
  end
end
