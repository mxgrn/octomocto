defmodule OctomoctoWeb.BlockRequestsTest do
  use OctomoctoWeb.ConnCase, async: true

  alias Octomocto.Blocklist

  # Test requests come from 127.0.0.1, so the entry also has a user agent
  # that only this test sends.
  setup do
    {:ok, entry} = Blocklist.create_entry(%{ip: "127.0.0.1", user_agent: "BlockRequestsTestBot"})
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
    _ = :sys.get_state(Blocklist.Cache)
    :ok
  end

  test "sends a plain 404 to a blocked client", %{conn: conn} do
    conn = conn |> put_req_header("user-agent", "BlockRequestsTestBot/1.0") |> get(~p"/memory")

    assert conn.status == 404
    assert conn.resp_body == "Not Found"
  end

  test "serves other clients", %{conn: conn} do
    conn = conn |> put_req_header("user-agent", "Mozilla/5.0") |> get(~p"/memory")

    assert conn.status == 200
  end
end
