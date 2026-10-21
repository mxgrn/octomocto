defmodule OctomoctoWeb.SiteNotificationsTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.NotificationsFixtures

  alias OctomoctoWeb.SiteNotifications

  describe "to_html/1" do
    test "gives the inline HTML of the Markdown" do
      assert SiteNotifications.to_html("Try [Overlap](/overlap) **now**") ==
               ~s(Try <a href="/overlap">Overlap</a> <strong>now</strong>)
    end

    test "omits raw HTML" do
      refute SiteNotifications.to_html("Hi <script>alert(1)</script>") =~ "<script>"
    end
  end

  test "a game page shows the site-wide and the game notifications", %{conn: conn} do
    site_wide = notification_fixture()
    memory = notification_fixture(game: "memory")
    trains = notification_fixture(game: "trains")

    {:ok, view, _html} = live(conn, ~p"/memory")

    assert has_element?(view, "#site-notification-#{site_wide.id}")
    assert has_element?(view, "#site-notification-#{memory.id}")
    refute has_element?(view, "#site-notification-#{trains.id}")
  end

  test "a page without a game shows only the site-wide notifications", %{conn: conn} do
    site_wide = notification_fixture()
    memory = notification_fixture(game: "memory")

    html = conn |> get(~p"/privacy") |> html_response(200)

    assert html =~ ~s(id="site-notification-#{site_wide.id}")
    refute html =~ ~s(id="site-notification-#{memory.id}")
  end

  test "the Pairs One banner hides the notifications", %{conn: conn} do
    notification_fixture()

    {:ok, view, _html} = live(conn, ~p"/memory?utm_source=pairs.one")

    assert has_element?(view, "#site-banner")
    refute has_element?(view, "#site-notifications")
  end
end
