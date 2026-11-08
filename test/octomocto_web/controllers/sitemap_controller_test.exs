defmodule OctomoctoWeb.SitemapControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  test "GET /sitemap.xml does not list the archived Station Escape", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    refute body =~ "/astronaut"
  end

  test "GET /sitemap.xml lists the FAQ page in each language", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    for path <- ["/faq" | Enum.map(OctomoctoWeb.Locale.other_locales(), &"/#{&1}/faq")] do
      assert body =~ "<loc>#{OctomoctoWeb.Endpoint.url()}#{path}</loc>"
    end
  end
end
