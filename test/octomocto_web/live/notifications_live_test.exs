defmodule OctomoctoWeb.NotificationsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.{Friends, Notifications}

  describe "a guest" do
    test "has the Notifications link in the menu", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, ~s(#guest-menu #notifications-link[href="/notifications"]))
    end

    test "sees the broadcasts from after the first visit", %{conn: conn} do
      {:ok, old} = Notifications.create_broadcast(%{text: "Old news"})
      conn = get(conn, ~p"/")
      {:ok, new} = Notifications.create_broadcast(%{text: "New [game](/graze)"})

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(
               view,
               ~s|#notifications-broadcast-#{new.id}[data-new="true"] a[href="/graze"]|
             )

      refute has_element?(view, "#notifications-broadcast-#{old.id}")
      assert has_element?(view, "#notifications-sign-in")
    end

    test "sees the dot on the menu when a broadcast is unread", %{conn: conn} do
      conn = get(conn, ~p"/")
      Notifications.create_broadcast(%{text: "New game"})

      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#guest-menu #notifications-dot[hidden]")
      assert view |> element("#guest-menu #notifications-count") |> render() =~ "1"
    end

    test "opening the page marks the broadcasts read", %{conn: conn} do
      conn = get(conn, ~p"/")
      Notifications.create_broadcast(%{text: "New game"})

      conn = get(conn, ~p"/notifications")
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#guest-menu #notifications-dot[hidden]")
    end

    test "gets a new broadcast while a page is open", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      Notifications.create_broadcast(%{text: "New game"})

      assert_push_event(view, "unread-notifications", %{count: 1})
    end

    test "comes back to the page after sign-in", %{conn: conn} do
      conn = get(conn, ~p"/notifications")
      assert get_session(conn, :user_return_to) == "/notifications"
    end
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

      assert has_element?(view, ~s|#notifications-follow-#{notification.id}[data-new="true"]|)
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

    test "sees the broadcasts on the page", %{conn: conn} do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "New game"})

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notifications-broadcast-#{broadcast.id}", "New game")
      refute has_element?(view, "#notifications-sign-in")
    end
  end
end
