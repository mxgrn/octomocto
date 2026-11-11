defmodule OctomoctoWeb.Admin.BroadcastsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Notifications

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
    |> render_submit()

    assert_redirect(view, ~p"/admin/notifications")
    assert [%{text: "New [game](/graze)"}] = Notifications.list_broadcasts()
  end

  test "shows the errors of an invalid broadcast", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/notifications/new")

    view |> form("#broadcast-form", broadcast: %{text: ""}) |> render_submit()

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
