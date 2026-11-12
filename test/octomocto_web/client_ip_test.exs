defmodule OctomoctoWeb.ClientIpTest do
  use ExUnit.Case, async: true

  alias Octomocto.IpRange
  alias OctomoctoWeb.ClientIp

  @balancer {10, 0, 0, 5}

  defp trusted, do: [elem(IpRange.parse("10.0.0.5"), 1)]

  test "takes the IP that the load balancer adds" do
    assert ClientIp.client_ip(@balancer, ["203.0.113.7"], trusted()) == {203, 0, 113, 7}
  end

  test "ignores the IPs that the client sends itself" do
    # nginx adds the real IP at the end of the client's header
    assert ClientIp.client_ip(@balancer, ["1.2.3.4, 203.0.113.7"], trusted()) ==
             {203, 0, 113, 7}
  end

  test "ignores the header from a sender that is not a trusted proxy" do
    assert ClientIp.client_ip({198, 51, 100, 1}, ["203.0.113.7"], trusted()) ==
             {198, 51, 100, 1}
  end

  test "keeps the sender IP when the header is missing or invalid" do
    assert ClientIp.client_ip(@balancer, [], trusted()) == @balancer
    assert ClientIp.client_ip(@balancer, ["unknown"], trusted()) == @balancer
  end

  test "changes an IPv4 address mapped in IPv6 to IPv4" do
    assert ClientIp.client_ip({0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107}, [], []) ==
             {203, 0, 113, 7}
  end
end
