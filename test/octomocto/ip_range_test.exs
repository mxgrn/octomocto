defmodule Octomocto.IpRangeTest do
  use ExUnit.Case, async: true

  alias Octomocto.IpRange

  test "parses an IP and a CIDR range to their normal text" do
    assert {:ok, range} = IpRange.parse(" 203.0.113.7 ")
    assert IpRange.to_string(range) == "203.0.113.7"

    # The host bits are cleared
    assert {:ok, range} = IpRange.parse("203.0.113.9/24")
    assert IpRange.to_string(range) == "203.0.113.0/24"

    assert {:ok, range} = IpRange.parse("2001:DB8::1/64")
    assert IpRange.to_string(range) == "2001:db8::/64"
  end

  test "rejects invalid text" do
    for text <- ["", "203.0.113", "203.0.113.7/33", "2001:db8::/129", "x/24", "1.2.3.4/x"] do
      assert IpRange.parse(text) == :error, text
    end
  end

  test "finds if an IP is in a range" do
    {:ok, range} = IpRange.parse("203.0.113.0/24")

    assert IpRange.member?(range, {203, 0, 113, 200})
    refute IpRange.member?(range, {203, 0, 114, 1})
    refute IpRange.member?(range, {0, 0, 0, 0, 0, 0, 0, 1})
  end

  test "an IPv4 address mapped in IPv6 is the IPv4 address" do
    {:ok, range} = IpRange.parse("203.0.113.7")

    assert IpRange.member?(range, {0, 0, 0, 0, 0, 0xFFFF, 0xCB00, 0x7107})
  end
end
