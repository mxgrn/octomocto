defmodule OctomoctoWeb.HreflangTest do
  use OctomoctoWeb.ConnCase

  # A URL with a query or a tab URL has the canonical link of the page
  # without them, so only that page has the hreflang links

  defp hreflangs(conn, path) do
    html_response(get(conn, path), 200)
    |> LazyHTML.from_document()
    |> LazyHTML.query(~s(link[rel="alternate"][hreflang]))
    |> LazyHTML.attribute("hreflang")
  end

  for path <- ["/", "/pt", "/echo", "/memory", "/set", "/faq"] do
    test "#{path} has the hreflang links", %{conn: conn} do
      assert "x-default" in hreflangs(conn, unquote(path))
    end
  end

  for path <- [
        "/?tag=memory",
        "/echo?pads=2&players=1",
        "/echo/lobby",
        "/pt/echo?pads=2&players=1",
        "/memory?cards=16",
        "/memory/lobby",
        "/memory/campaign",
        "/set?players=1",
        "/set/lobby",
        "/faq?utm_source=x"
      ] do
    test "#{path} has no hreflang links", %{conn: conn} do
      assert hreflangs(conn, unquote(path)) == []
    end
  end
end
