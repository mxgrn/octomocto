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

    test "sees the line breaks and the paragraphs of a broadcast", %{conn: conn} do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hi!\nNews:\n\nNew game"})

      {:ok, view, _html} = live(conn, ~p"/notifications")

      assert has_element?(view, "#notifications-broadcast-#{broadcast.id} p br")
      assert has_element?(view, "#notifications-broadcast-#{broadcast.id} p", "New game")
    end
  end

  describe "in a language" do
    test "a guest sees the broadcasts in the language", %{conn: conn} do
      conn = get(conn, ~p"/pt")
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "New game"})
      add_translation("pt", "New game", "Jogo novo")

      {:ok, view, _html} = live(conn, ~p"/pt/notifications")

      assert has_element?(view, "#notifications-broadcast-#{broadcast.id}", "Jogo novo")
      assert has_element?(view, ~s(#notifications-sign-in-link[href="/pt/signin"]))
    end

    test "the language selector links to the page in the other languages", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pt/notifications")

      assert has_element?(
               view,
               ~s|#language-switcher #language-en[href="#{~p"/locale/en?#{[to: "/notifications"]}"}"]|
             )

      assert has_element?(
               view,
               ~s|#language-switcher #language-de[href="#{~p"/locale/de?#{[to: "/de/notifications"]}"}"]|
             )
    end

    test "the menu links to the notifications in the language", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pt")
      assert has_element?(view, ~s(#notifications-link[href="/pt/notifications"]))
    end

    test "a browser in the language goes to the notifications in the language",
         %{conn: conn} do
      conn =
        conn
        |> put_req_header("user-agent", "Mozilla/5.0")
        |> put_req_header("accept-language", "pt-BR")
        |> get(~p"/notifications")

      assert redirected_to(conn) == "/pt/notifications"
    end
  end

  # The translation that the LLM gives (see `Octomocto.Notifications.translate/1`)
  defp add_translation(locale, text, value) do
    Octomocto.Repo.insert!(%Understudy.Translation{
      locale: locale,
      domain: "broadcasts",
      text: text,
      text_hash: :crypto.hash(:sha256, text),
      value: value,
      last_used_at: NaiveDateTime.utc_now(:second)
    })
  end
end
