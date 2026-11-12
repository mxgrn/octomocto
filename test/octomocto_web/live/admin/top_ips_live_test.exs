defmodule OctomoctoWeb.Admin.TopIpsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.{Blocklist, RecentRequests}
  alias OctomoctoWeb.Admin.TopIpsLive

  setup :register_and_log_in_admin

  # The buffer is the same for all tests, so each test uses its own IP
  setup do
    n = System.unique_integer([:positive])
    ip = {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}

    for _ <- 1..2,
        do: RecentRequests.record(ip, "TopIpsTestBot/1.0", "GET", "/pt/memory")

    ip = ip |> :inet.ntoa() |> to_string()
    %{ip: ip, row: "#" <> TopIpsLive.row_id(ip)}
  end

  test "shows the IP with its requests and user agents", %{conn: conn, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/top-ips")

    assert has_element?(view, "#{row} [data-role=count]", "2")
    assert has_element?(view, row, "TopIpsTestBot/1.0")
  end

  test "blocks the IP", %{conn: conn, ip: ip, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/top-ips")

    view |> element("#{row} [data-role=block-ip]") |> render_click()

    assert [%{ip: ^ip, user_agent: nil} = entry] = Blocklist.list_entries()
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
    assert has_element?(view, "#{row} [data-role=blocked]")
  end

  test "blocks the IP with a user agent", %{conn: conn, ip: ip, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/top-ips")

    view |> element("#{row} [data-role=block-ip-user-agent]") |> render_click()

    assert [%{ip: ^ip, user_agent: "TopIpsTestBot/1.0"} = entry] =
             Blocklist.list_entries()

    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
  end
end
