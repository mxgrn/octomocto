defmodule OctomoctoWeb.PageControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET / links to all games", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    hrefs =
      document
      |> LazyHTML.query("#games a")
      |> LazyHTML.attribute("href")

    assert hrefs == ["/trains", "/astronaut", "/schulte"]
  end

  test "the hero shows the slogan", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#hero #slogan") |> LazyHTML.text() =~ "Use your heads"
  end

  test "the page title has the tagline", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "title") |> LazyHTML.text() ==
             "Octomocto · Brain Games to Play Solo or with Friends"
  end

  test "the page has the description meta tag", %{conn: conn} do
    conn = get(conn, ~p"/")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, ~s(meta[name="description"]))
           |> LazyHTML.attribute("content") == [
             "Quick brain games for memory, logic and speed. Play solo or go head to head with friends."
           ]
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

    assert LazyHTML.query(home, "#home-link svg.h-8") |> Enum.count() == 1
    assert LazyHTML.query(game, "#home-link svg.h-6") |> Enum.count() == 1
  end

  test "game pages use the full width", %{conn: conn} do
    home = LazyHTML.from_document(html_response(get(conn, ~p"/"), 200))
    game = LazyHTML.from_document(html_response(get(conn, ~p"/trains"), 200))

    assert LazyHTML.query(home, "main > .max-w-2xl") |> Enum.count() == 1
    assert LazyHTML.query(game, "main > .max-w-2xl") |> Enum.count() == 0
  end

  test "GET /elm renders the Elm mount node", %{conn: conn} do
    conn = get(conn, ~p"/elm")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#elm-main") |> Enum.count() == 1
  end
end
