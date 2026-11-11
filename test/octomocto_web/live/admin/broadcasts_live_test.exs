defmodule OctomoctoWeb.Admin.BroadcastsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Notifications
  alias Octomocto.Notifications.Broadcast

  setup :register_and_log_in_admin

  test "lists the broadcasts", %{conn: conn} do
    {:ok, broadcast} = Notifications.create_broadcast(%{text: "Try [Graze](/graze)"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    assert has_element?(view, "#broadcasts-#{broadcast.id} a[href='/graze']", "Graze")
  end

  test "creates a broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view
    |> form("#broadcast-form", broadcast: %{text: "New [game](/graze)"})
    |> render_submit(%{status: "sent"})

    assert_redirect(view, ~p"/admin/notifications")
    assert [%{text: "New [game](/graze)"}] = Notifications.list_broadcasts()
  end

  test "sends a test, then sends the same broadcast to all", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view
    |> form("#broadcast-form", broadcast: %{text: "Typo"})
    |> render_submit(%{status: "test"})

    assert [%{id: id, text: "Typo", status: :test}] = Notifications.list_broadcasts()

    view
    |> form("#broadcast-form", broadcast: %{text: "Fixed"})
    |> render_submit(%{status: "sent"})

    assert_redirect(view, ~p"/admin/notifications")
    assert [%{id: ^id, text: "Fixed", status: :sent}] = Notifications.list_broadcasts()
  end

  test "sends a broadcast to the guests only", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view
    |> form("#broadcast-form", broadcast: %{text: "Sign up!", audience: "guests"})
    |> render_submit(%{status: "sent"})

    assert [%{audience: :guests}] = Notifications.list_broadcasts()
  end

  test "cannot change the audience of a sent broadcast", %{conn: conn} do
    {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hi"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications/#{broadcast}/edit")

    assert has_element?(view, "#broadcast-form select[name='broadcast[audience]'][disabled]")
  end

  test "marks the audience in the list", %{conn: conn} do
    {:ok, users} = Notifications.create_broadcast(%{text: "Hi", audience: :users})
    {:ok, all} = Notifications.create_broadcast(%{text: "Hi"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    assert has_element?(view, "#audience-badge-#{users.id}", "Users")
    refute has_element?(view, "#audience-badge-#{all.id}")
  end

  test "marks the test broadcasts in the list", %{conn: conn} do
    {:ok, test} = Notifications.send_test_broadcast(%Broadcast{}, %{text: "Hello"})
    {:ok, sent} = Notifications.create_broadcast(%{text: "Sent"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    assert has_element?(view, "#status-badge-#{test.id}", "Test")
    refute has_element?(view, "#status-badge-#{sent.id}")
  end

  test "shows the errors of an invalid broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view |> form("#broadcast-form", broadcast: %{text: ""}) |> render_submit(%{status: "sent"})

    assert has_element?(view, "#broadcast-form", "can't be blank")
  end

  test "changes a broadcast", %{conn: conn} do
    {:ok, broadcast} = Notifications.create_broadcast(%{text: "Typo"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications/#{broadcast}/edit")

    view |> form("#broadcast-form", broadcast: %{text: "Fixed"}) |> render_submit()

    assert_redirect(view, ~p"/admin/notifications")
    assert [%{text: "Fixed"}] = Notifications.list_broadcasts()
  end

  test "deletes a broadcast", %{conn: conn} do
    {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hello"})

    {:ok, view, _html} = live(conn, ~p"/admin/notifications")

    view |> element("#delete-broadcast-#{broadcast.id}") |> render_click()

    refute has_element?(view, "#broadcasts-#{broadcast.id}")
    assert Notifications.list_broadcasts() == []
  end
end
