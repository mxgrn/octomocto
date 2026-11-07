defmodule OctomoctoWeb.NotificationsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Friends, Notifications}

  test "a guest goes to the sign-in page", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/signin"}}} = live(conn, ~p"/notifications")
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "sees the dot on the avatar when a notification is unread",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#notifications-dot[hidden]")

      Friends.follow(user_fixture().id, user.id)

      {:ok, view, _html} = live(conn, ~p"/")
      refute has_element?(view, "#notifications-dot[hidden]")
      assert view |> element("#notifications-count") |> render() =~ "1"
    end

    test "gets the new count while a page is open", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      Friends.follow(user_fixture().id, user.id)

      assert_push_event(view, "unread-notifications", %{count: 1})
    end

    test "opening the page marks the notifications read", %{conn: conn, user: user} do
      follower = user_fixture()
      Friends.follow(follower.id, user.id)
      [notification] = Notifications.list(user.id)

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, ~s|#notifications-#{notification.id}[data-new="true"]|)
      assert Notifications.unread_count(user.id) == 0
    end

    test "Follow back follows the follower", %{conn: conn, user: user} do
      follower = user_fixture()
      Friends.follow(follower.id, user.id)
      [notification] = Notifications.list(user.id)
      {:ok, view, _html} = live(conn, ~p"/notifications")

      view |> element("#follow-back-#{notification.id}") |> render_click()

      assert has_element?(view, "#following-#{notification.id}")
      assert Friends.following?(user.id, follower.id)
    end
  end
end
