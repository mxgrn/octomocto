defmodule OctomoctoWeb.NotificationCloseControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  import Octomocto.NotificationsFixtures

  alias Octomocto.Notifications

  test "saves the close of a guest", %{conn: conn} do
    notification = notification_fixture()

    conn = post(conn, ~p"/notifications/#{notification.id}/close")

    assert response(conn, 204)
    assert Notifications.close_counts() == %{notification.id => 1}
  end

  test "a signed-in user does not see a closed notification again", %{conn: conn} do
    notification = notification_fixture()
    %{conn: conn} = register_and_log_in_user(%{conn: conn})

    post(conn, ~p"/notifications/#{notification.id}/close")
    html = conn |> get(~p"/privacy") |> html_response(200)

    refute html =~ ~s(id="site-notification-#{notification.id}")
  end

  test "gives 404 for an id that is not a number", %{conn: conn} do
    assert conn |> post(~p"/notifications/abc/close") |> response(404)
  end
end
