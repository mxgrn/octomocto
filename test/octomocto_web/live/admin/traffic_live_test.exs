defmodule OctomoctoWeb.Admin.TrafficLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.{Blocklist, RecentRequests}
  alias OctomoctoWeb.Admin.TrafficLive

  setup :register_and_log_in_admin

  # The buffer is the same for all tests, so each test uses its own IP
  setup do
    n = System.unique_integer([:positive])
    ip = {10, rem(div(n, 65_536), 256), rem(div(n, 256), 256), rem(n, 256)}

    for _ <- 1..2,
        do: RecentRequests.record(ip, "TrafficTestBot/1.0", "GET", "/pt/memory")

    ip = ip |> :inet.ntoa() |> to_string()
    %{ip: ip, row: "#" <> TrafficLive.row_id(ip)}
  end

  test "shows the IP with its requests and user agents", %{conn: conn, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/traffic")

    assert has_element?(view, "#{row} [data-role=count]", "2")
    assert has_element?(view, row, "TrafficTestBot/1.0")
  end

  test "blocks the IP", %{conn: conn, ip: ip, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/traffic")

    view |> element("#{row} [data-role=block-ip]") |> render_click()

    assert [%{ip: ^ip, user_agent: nil} = entry] = Blocklist.list_entries()
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
    assert has_element?(view, "#{row} [data-role=blocked]")
  end

  test "blocks the IP with a user agent", %{conn: conn, ip: ip, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/traffic")

    view |> element("#{row} [data-role=block-ip-user-agent]") |> render_click()

    assert [%{ip: ^ip, user_agent: "TrafficTestBot/1.0"} = entry] =
             Blocklist.list_entries()

    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
  end

  test "links to the blocklist form with the user agent", %{conn: conn, row: row} do
    {:ok, view, _html} = live(conn, ~p"/admin/traffic")

    view |> element("#{row} [data-role=block-user-agent]") |> render_click()

    assert_redirect(view, ~p"/admin/blocklist?#{[user_agent: "TrafficTestBot/1.0"]}")
  end

  describe "by user agent" do
    # Each test has its own bot name, from two IPs and two versions
    setup do
      name = "TrafficTest#{System.unique_integer([:positive])}bot"

      RecentRequests.record({192, 0, 2, 1}, "Mozilla/5.0 (compatible; #{name}/1.0)", "GET", "/")
      RecentRequests.record({192, 0, 2, 2}, "Mozilla/5.0 (compatible; #{name}/2.0)", "GET", "/")
      RecentRequests.record({192, 0, 2, 2}, "Mozilla/5.0 (compatible; #{name}/2.0)", "GET", "/")

      %{name: name, row: "#" <> TrafficLive.user_agent_row_id(name)}
    end

    test "groups the requests by the bot name", %{conn: conn, row: row} do
      {:ok, view, _html} = live(conn, ~p"/admin/traffic?by=user_agent")

      assert has_element?(view, "#{row} [data-role=count]", "3")
      assert has_element?(view, "#{row} [data-role=ip-count]", "2 IPs")
    end

    test "blocks the bot name from any IP", %{conn: conn, name: name, row: row} do
      {:ok, view, _html} = live(conn, ~p"/admin/traffic?by=user_agent")

      view |> element("#{row} [data-role=block-bot]") |> render_click()

      assert [%{ip: nil, user_agent: ^name} = entry] = Blocklist.list_entries()
      on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
      assert has_element?(view, "#{row} [data-role=blocked]")
    end
  end
end
