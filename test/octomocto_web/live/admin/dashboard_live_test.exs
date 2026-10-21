defmodule OctomoctoWeb.Admin.DashboardLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "is not found for a guest", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/admin") end
  end

  test "is not found for a user who is not an admin", %{conn: conn} do
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    assert_error_sent 404, fn -> get(conn, ~p"/admin/notifications") end
  end

  test "links to the notifications for an admin", %{conn: conn} do
    %{conn: conn} = register_and_log_in_admin(%{conn: conn})

    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-notifications-link[href='/admin/notifications']")
  end
end
