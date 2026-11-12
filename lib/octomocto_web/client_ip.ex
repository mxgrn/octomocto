defmodule OctomoctoWeb.ClientIp do
  @moduledoc """
  Puts the IP of the real client in `conn.remote_ip`, and adds it and the
  user agent to the Logger metadata of the request.

  nginx on the load balancer opens the connection to the app, and puts the
  client IP at the end of the X-Forwarded-For header. A client can send this
  header too, with any IPs. Thus, the plug reads the header only when the
  connection comes from a trusted proxy (the `:trusted_proxies` config, from
  the TRUSTED_PROXIES env var), and takes the last IP that is not a trusted
  proxy.
  """
  @behaviour Plug

  import Plug.Conn

  alias Octomocto.IpRange

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    trusted =
      :octomocto
      |> Application.get_env(:trusted_proxies, [])
      |> Enum.map(fn text -> elem(IpRange.parse(text), 1) end)

    ip = client_ip(conn.remote_ip, get_req_header(conn, "x-forwarded-for"), trusted)
    user_agent = conn |> get_req_header("user-agent") |> List.first()

    Logger.metadata(remote_ip: ip |> :inet.ntoa() |> to_string(), user_agent: user_agent)
    %{conn | remote_ip: ip}
  end

  @doc """
  Gives the client IP from the `remote_ip` of the connection, the values of
  the X-Forwarded-For headers and the `trusted` proxy ranges.
  """
  def client_ip(remote_ip, forwarded_for, trusted) do
    remote_ip = IpRange.normalize(remote_ip)

    if trusted?(remote_ip, trusted) do
      forwarded_for
      |> Enum.flat_map(&String.split(&1, ","))
      |> Enum.reverse()
      |> Enum.reduce_while(remote_ip, fn text, _ip ->
        case :inet.parse_strict_address(String.to_charlist(String.trim(text))) do
          {:ok, ip} ->
            ip = IpRange.normalize(ip)
            if trusted?(ip, trusted), do: {:cont, ip}, else: {:halt, ip}

          {:error, _} ->
            {:halt, remote_ip}
        end
      end)
    else
      remote_ip
    end
  end

  defp trusted?(ip, trusted), do: Enum.any?(trusted, &IpRange.member?(&1, ip))
end
