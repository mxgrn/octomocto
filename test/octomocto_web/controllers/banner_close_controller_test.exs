defmodule OctomoctoWeb.BannerCloseControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  import Octomocto.BannersFixtures

  alias Octomocto.Banners

  test "saves the close of a guest", %{conn: conn} do
    banner = banner_fixture()

    conn = post(conn, ~p"/banners/#{banner.id}/close")

    assert response(conn, 204)
    assert Banners.close_counts() == %{banner.id => 1}
  end

  test "a signed-in user does not see a closed banner again", %{conn: conn} do
    banner = banner_fixture()
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    post(conn, ~p"/banners/#{banner.id}/close")
    html = conn |> get(~p"/privacy") |> html_response(200)

    refute html =~ ~s(id="site-banner-#{banner.id}")
  end

  test "gives 404 for an id that is not a number", %{conn: conn} do
    assert conn |> post(~p"/banners/abc/close") |> response(404)
  end
end
