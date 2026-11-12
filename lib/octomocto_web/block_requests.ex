defmodule OctomoctoWeb.BlockRequests do
  @moduledoc """
  Keeps each request in `Octomocto.RecentRequests` (for /admin/traffic), and
  sends a plain 404 to the clients in `Octomocto.Blocklist`.

  A 404 does not tell a bot that it is blocked, so it has less reason to
  change its IP. The blocked requests are also in the recent requests, so
  that the admins see if a blocked bot continues.

  Comes after `OctomoctoWeb.ClientIp`, which gives the real client IP, and
  before `Plug.Telemetry`: a blocked request has its own log line, with
  `blocked=true`, instead of the usual two lines.
  """
  @behaviour Plug

  require Logger

  import Plug.Conn

  alias Octomocto.{Blocklist, RecentRequests}

  # The deploys check this path
  @not_recorded ["/health"]

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    user_agent = conn |> get_req_header("user-agent") |> List.first()

    if conn.request_path not in @not_recorded do
      RecentRequests.record(conn.remote_ip, user_agent, conn.method, conn.request_path)
    end

    if Blocklist.blocked?(conn.remote_ip, user_agent) do
      Logger.info("Blocked #{conn.method} #{conn.request_path}", blocked: true)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(404, "Not Found")
      |> halt()
    else
      conn
    end
  end
end
