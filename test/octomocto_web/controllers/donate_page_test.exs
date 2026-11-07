defmodule OctomoctoWeb.DonatePageTest do
  use OctomoctoWeb.ConnCase

  test "the donate page links to Patreon", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/donate"), 200))

    assert LazyHTML.query(document, "#donate-patreon") |> LazyHTML.attribute("href") == [
             "https://patreon.com/mxgrn"
           ]
  end

  test "the donate page has the language of its prefix", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/de/donate"), 200))

    assert LazyHTML.query(document, "#donate-patreon") |> LazyHTML.text() =~
             "Auf Patreon unterstützen"
  end

  test "the footer links to the donate page in the language of the page", %{conn: conn} do
    english = LazyHTML.from_document(html_response(get(conn, ~p"/"), 200))
    german = LazyHTML.from_document(html_response(get(conn, ~p"/de/memory"), 200))

    assert LazyHTML.query(english, "#donate-link") |> LazyHTML.attribute("href") == ["/donate"]
    assert LazyHTML.query(german, "#donate-link") |> LazyHTML.attribute("href") == ["/de/donate"]
  end
end
