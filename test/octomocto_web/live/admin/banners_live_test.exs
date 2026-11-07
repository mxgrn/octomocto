defmodule OctomoctoWeb.Admin.BannersLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures
  import Octomocto.BannersFixtures

  alias Octomocto.Banners

  setup :register_and_log_in_admin

  test "lists the banners", %{conn: conn} do
    banner = banner_fixture(text: "Try [Overlap](/overlap)", game: "memory")

    {:ok, view, _html} = live(conn, ~p"/admin/banners")

    assert has_element?(view, "#banners-#{banner.id} a[href='/overlap']", "Overlap")
    assert has_element?(view, "#banners-#{banner.id}", "Memory")
  end

  test "shows the number of closes", %{conn: conn} do
    banner = banner_fixture()
    Banners.record_close(banner.id, user_scope_fixture(), nil)

    {:ok, view, _html} = live(conn, ~p"/admin/banners")

    assert has_element?(view, "#banner-closes-#{banner.id}", "1 closed")
  end

  test "creates a banner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/banners/new")

    view
    |> form("#banner-form",
      banner: %{text: "New [game](/overlap)", game: "", expires_at: "2030-01-01T12:00"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/admin/banners")

    assert [%{text: "New [game](/overlap)", game: nil, expires_at: ~U[2030-01-01 12:00:00Z]}] =
             Banners.list_banners()
  end

  test "shows the errors of an invalid banner", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/banners/new")

    view |> form("#banner-form", banner: %{text: ""}) |> render_submit()

    assert has_element?(view, "#banner-form", "can't be blank")
  end

  test "changes a banner", %{conn: conn} do
    banner = banner_fixture()

    {:ok, view, _html} = live(conn, ~p"/admin/banners/#{banner}/edit")

    view
    |> form("#banner-form", banner: %{text: "Changed"})
    |> render_submit()

    assert_redirect(view, ~p"/admin/banners")
    assert Banners.get_banner!(banner.id).text == "Changed"
  end

  test "deletes a banner", %{conn: conn} do
    banner = banner_fixture()

    {:ok, view, _html} = live(conn, ~p"/admin/banners")

    view |> element("#delete-banner-#{banner.id}") |> render_click()

    refute has_element?(view, "#banners-#{banner.id}")
    assert Banners.list_banners() == []
  end
end
