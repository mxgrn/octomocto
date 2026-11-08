defmodule OctomoctoWeb.FaqPageTest do
  use OctomoctoWeb.ConnCase

  import Octomocto.AccountsFixtures

  test "the table of contents links to each answer", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/faq"), 200))
    hrefs = LazyHTML.query(document, "#faq-toc a") |> LazyHTML.attribute("href")

    assert length(hrefs) == 6

    for "#" <> id <- hrefs do
      assert LazyHTML.query(document, "section##{id}") |> Enum.count() == 1
    end
  end

  test "the FAQ page has the language of its prefix", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/de/faq"), 200))

    assert LazyHTML.query(document, "#faq-free h2") |> LazyHTML.text() =~
             "Ist Octomocto kostenlos?"
  end

  test "the menu links to the FAQ page in the language of the page", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/de"), 200))

    assert LazyHTML.query(document, "#guest-menu #faq-link") |> LazyHTML.attribute("href") ==
             ["/de/faq"]
  end

  test "the guest menu links to the FAQ page", %{conn: conn} do
    document = LazyHTML.from_document(html_response(get(conn, ~p"/"), 200))

    assert LazyHTML.query(document, "#guest-menu #faq-link") |> LazyHTML.attribute("href") ==
             ["/faq"]
  end

  test "the user menu links to the FAQ page and to the game suggestions", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    document = LazyHTML.from_document(html_response(get(conn, ~p"/"), 200))

    assert LazyHTML.query(document, "#user-menu #faq-link") |> LazyHTML.attribute("href") ==
             ["/faq"]

    assert LazyHTML.query(document, "#user-menu #suggest-game-link")
           |> LazyHTML.attribute("href") == ["mailto:hi@octomocto.com"]
  end
end
