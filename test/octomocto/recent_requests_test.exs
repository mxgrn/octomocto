defmodule Octomocto.RecentRequestsTest do
  use ExUnit.Case, async: true

  alias Octomocto.RecentRequests

  setup do
    start_supervised!({RecentRequests, name: :recent_requests_test, size: 3})
    %{table: :recent_requests_test}
  end

  test "groups the requests by IP, the most requests first", %{table: table} do
    RecentRequests.record(table, {192, 0, 2, 1}, "bot", "GET", "/pt/memory")
    RecentRequests.record(table, {192, 0, 2, 2}, "Chrome", "GET", "/")
    RecentRequests.record(table, {192, 0, 2, 2}, nil, "GET", "/es/memory")

    assert [
             %{ip: "192.0.2.2", count: 2, user_agents: [{_, 1}, {_, 1}]},
             %{ip: "192.0.2.1", count: 1, user_agents: [{"bot", 1}], last_path: "/pt/memory"}
           ] = RecentRequests.top_ips([RecentRequests.summary(table)])
  end

  test "keeps only the last requests", %{table: table} do
    RecentRequests.record(table, {192, 0, 2, 1}, nil, "GET", "/")

    for _ <- 1..3, do: RecentRequests.record(table, {192, 0, 2, 2}, nil, "GET", "/")

    assert [%{ip: "192.0.2.2", count: 3}] =
             RecentRequests.top_ips([RecentRequests.summary(table)])
  end

  test "adds the counts of the nodes" do
    at = DateTime.utc_now()

    node1 = %{
      "192.0.2.1" => %{count: 2, user_agents: %{"bot" => 2}, last_at: at, last_path: "/a"}
    }

    node2 = %{
      "192.0.2.1" => %{count: 1, user_agents: %{"bot" => 1}, last_at: at, last_path: "/b"}
    }

    assert [%{ip: "192.0.2.1", count: 3, user_agents: [{"bot", 3}]}] =
             RecentRequests.top_ips([node1, node2])
  end
end
