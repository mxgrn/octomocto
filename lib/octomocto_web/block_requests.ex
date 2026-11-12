defmodule OctomoctoWeb.BlockRequests do
  @moduledoc """
  Sends a plain 404 to the clients in `Octomocto.Blocklist`, and keeps each
  served request in `Octomocto.RecentRequests` (for /admin/traffic).

  A 404 does not tell a bot that it is blocked, so it has less reason to
  change its IP. The blocked requests are not in the recent requests, so
  that they do not push the real traffic out. To see if a blocked bot
  continues, turn on the log of its entry.

  Comes after `OctomoctoWeb.ClientIp`, which gives the real client IP, and
  before `Plug.Telemetry`, so that a blocked request has none of the usual
  log lines. It has one line with `blocked=true` only when its entry has the
  log on.
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

    case Blocklist.check(conn.remote_ip, user_agent) do
      nil ->
        if conn.request_path not in @not_recorded do
          RecentRequests.record(conn.remote_ip, user_agent, conn.method, conn.request_path)
        end

        conn

      log ->
        if log == :log,
          do: Logger.info("Blocked #{conn.method} #{conn.request_path}", blocked: true)

        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(404, "Not Found")
        |> halt()
    end
  end
end
