defmodule OctomoctoWeb.SiteBannersTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.BannersFixtures

  alias OctomoctoWeb.SiteBanners

  describe "to_html/1" do
    test "gives the inline HTML of the Markdown" do
      assert SiteBanners.to_html("Try [Overlap](/overlap) **now**") ==
               ~s(Try <a href="/overlap">Overlap</a> <strong>now</strong>)
    end

    test "omits raw HTML" do
      refute SiteBanners.to_html("Hi <script>alert(1)</script>") =~ "<script>"
    end
  end

  test "a game page shows the site-wide and the game banners", %{conn: conn} do
    site_wide = banner_fixture()
    memory = banner_fixture(game: "memory")
    trains = banner_fixture(game: "trains")

    {:ok, view, _html} = live(conn, ~p"/memory")

    assert has_element?(view, "#site-banner-#{site_wide.id}")
    assert has_element?(view, "#site-banner-#{memory.id}")
    refute has_element?(view, "#site-banner-#{trains.id}")
  end

  test "a page without a game shows only the site-wide banners", %{conn: conn} do
    site_wide = banner_fixture()
    memory = banner_fixture(game: "memory")

    html = conn |> get(~p"/privacy") |> html_response(200)

    assert html =~ ~s(id="site-banner-#{site_wide.id}")
    refute html =~ ~s(id="site-banner-#{memory.id}")
  end

  test "the Pairs One welcome line hides the banners", %{conn: conn} do
    banner_fixture()

    {:ok, view, _html} = live(conn, ~p"/memory?utm_source=pairs.one")

    assert has_element?(view, "#site-welcome")
    refute has_element?(view, "#site-banners")
  end
end
