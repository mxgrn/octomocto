defmodule OctomoctoWeb.Admin.BlocklistLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Blocklist

  setup :register_and_log_in_admin

  test "adds an entry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/blocklist")

    view
    |> form("#blocklist-form",
      entry: %{ip: "203.0.113.0/24", user_agent: "curl", note: "scraper"}
    )
    |> render_submit()

    assert [entry] = Blocklist.list_entries()
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
    assert has_element?(view, "#entries-#{entry.id}", "203.0.113.0/24")
  end

  test "shows the errors of an invalid entry", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/blocklist")

    view |> form("#blocklist-form", entry: %{ip: "203.0.113"}) |> render_submit()

    assert has_element?(view, "#blocklist-form", "is not an IP or a CIDR range")
  end

  test "deletes an entry", %{conn: conn} do
    {:ok, entry} = Blocklist.create_entry(%{ip: "203.0.113.8"})
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)

    {:ok, view, _html} = live(conn, ~p"/admin/blocklist")
    view |> element("#delete-entry-#{entry.id}") |> render_click()

    assert Blocklist.list_entries() == []
    refute has_element?(view, "#entries-#{entry.id}")
  end
end
