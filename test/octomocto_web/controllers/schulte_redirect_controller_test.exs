defmodule OctomoctoWeb.SchulteRedirectControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /schulte goes to /nimble-mosaic with the settings and a notice", %{conn: conn} do
    conn = get(conn, "/schulte?board=random")

    assert conn.status == 302
    assert redirected_to(conn) == "/nimble-mosaic?board=random"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Nimble Mosaic"
  end

  test "GET /schulte/:id goes to the same game in Nimble Mosaic", %{conn: conn} do
    conn = get(conn, "/schulte/abc123")

    assert redirected_to(conn, 302) == "/nimble-mosaic/abc123"
  end

  test "GET /stats/schulte goes to the Nimble Mosaic stats", %{conn: conn} do
    conn = get(conn, "/stats/schulte")

    assert redirected_to(conn, 302) == "/stats/nimble-mosaic"
  end
end
