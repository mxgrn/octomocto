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

  test "GET /elm renders the Elm mount node", %{conn: conn} do
    conn = get(conn, ~p"/elm")

    document = LazyHTML.from_document(html_response(conn, 200))

    assert LazyHTML.query(document, "#elm-main") |> Enum.count() == 1
  end
end
