defmodule OctomoctoWeb.SitemapControllerTest do
  # Not async: the lastmod tests change the application environment.
  use OctomoctoWeb.ConnCase, async: false

  test "GET /sitemap.xml does not list the archived Station Escape", %{conn: conn} do
    body = conn |> get(~p"/sitemap.xml") |> response(200)

    refute body =~ "/astronaut"
  end

  describe "lastmod" do
    setup do
      previous = Application.get_env(:octomocto, :deployed_on)
      on_exit(fn -> Application.put_env(:octomocto, :deployed_on, previous) end)
    end

    test "every URL has the deploy date as lastmod", %{conn: conn} do
      Application.put_env(:octomocto, :deployed_on, "2026-11-08")

      body = conn |> get(~p"/sitemap.xml") |> response(200)

      url_count = length(Regex.scan(~r/<url>/, body))
      lastmod_count = length(Regex.scan(~r{<lastmod>2026-11-08</lastmod>}, body))
      assert url_count > 0
      assert lastmod_count == url_count
    end

    test "there is no lastmod without a deploy date", %{conn: conn} do
      Application.put_env(:octomocto, :deployed_on, nil)

      body = conn |> get(~p"/sitemap.xml") |> response(200)

      refute body =~ "<lastmod>"
    end
  end
end
