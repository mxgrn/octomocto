defmodule OctomoctoWeb.Admin.NotificationsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.NotificationsFixtures

  alias Octomocto.Notifications

  setup :register_and_log_in_admin

  test "lists the notifications", %{conn: conn} do
    notification = notification_fixture(text: "Try [Overlap](/overlap)", game: "memory")

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    assert has_element?(view, "#notifications-#{notification.id} a[href='/overlap']", "Overlap")
    assert has_element?(view, "#notifications-#{notification.id}", "Memory")
  end

  test "creates a notification", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view
    |> form("#notification-form",
      notification: %{text: "New [game](/overlap)", game: "", expires_at: "2030-01-01T12:00"}
    )
    |> render_submit()

    assert_redirect(view, ~p"/admin/notifications")

    assert [%{text: "New [game](/overlap)", game: nil, expires_at: ~U[2030-01-01 12:00:00Z]}] =
             Notifications.list_notifications()
  end

  test "shows the errors of an invalid notification", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view |> form("#notification-form", notification: %{text: ""}) |> render_submit()

    assert has_element?(view, "#notification-form", "can't be blank")
  end

  test "changes a notification", %{conn: conn} do
    notification = notification_fixture()

    {:ok, view, _html} = live(conn, ~p"/admin/notifications/#{notification}/edit")

    view
    |> form("#notification-form", notification: %{text: "Changed"})
    |> render_submit()

    assert_redirect(view, ~p"/admin/notifications")
    assert Notifications.get_notification!(notification.id).text == "Changed"
  end

  test "deletes a notification", %{conn: conn} do
    notification = notification_fixture()

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    view |> element("#delete-notification-#{notification.id}") |> render_click()

    refute has_element?(view, "#notifications-#{notification.id}")
    assert Notifications.list_notifications() == []
  end
end
