defmodule OctomoctoWeb.SitemapControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  test "GET /sitemap.xml does not list the archived Station Escape", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    refute body =~ "/astronaut"
  end
end
