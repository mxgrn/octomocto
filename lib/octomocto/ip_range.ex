defmodule Octomocto.IpRange do
  @moduledoc """
  One IP address or a CIDR range of addresses, IPv4 or IPv6. A single
  address is a range with all bits in the prefix (/32 or /128).
  """

  @enforce_keys [:address, :prefix]
  defstruct [:address, :prefix]

  @type t :: %__MODULE__{address: :inet.ip_address(), prefix: non_neg_integer()}

  @doc """
  Parses "203.0.113.7" or "203.0.113.0/24". Clears the host bits of a
  range, so "203.0.113.9/24" gives the range "203.0.113.0/24".
  """
  def parse(text) when is_binary(text) do
    {address, prefix} =
      case String.split(String.trim(text), "/") do
        [address] -> {address, nil}
        [address, prefix] -> {address, prefix}
        _ -> {nil, nil}
      end

    with true <- is_binary(address),
         {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(address)),
         ip = normalize(ip),
         {:ok, prefix} <- parse_prefix(prefix, bits(ip)) do
      {:ok, %__MODULE__{address: mask(ip, prefix), prefix: prefix}}
    else
      _ -> :error
    end
  end

  defp parse_prefix(nil, bits), do: {:ok, bits}

  defp parse_prefix(text, bits) do
    case Integer.parse(text) do
      {prefix, ""} when prefix in 0..bits//1 -> {:ok, prefix}
      _ -> :error
    end
  end

  @doc "Gives true when the `ip` tuple is in the `range`."
  def member?(%__MODULE__{address: address, prefix: prefix}, ip) do
    ip = normalize(ip)
    tuple_size(ip) == tuple_size(address) and mask(ip, prefix) == address
  end

  @doc "Gives the normal text of the range, without the prefix for a single address."
  def to_string(%__MODULE__{address: address, prefix: prefix}) do
    text = address |> :inet.ntoa() |> List.to_string()
    if prefix == bits(address), do: text, else: "#{text}/#{prefix}"
  end

  @doc """
  Changes an IPv4 address mapped in IPv6 (::ffff:203.0.113.7) to the
  IPv4 address. A server that listens on IPv6 gets IPv4 clients in this form.
  """
  def normalize({0, 0, 0, 0, 0, 0xFFFF, high, low}) do
    <<a, b, c, d>> = <<high::16, low::16>>
    {a, b, c, d}
  end

  def normalize(ip), do: ip

  defp bits(ip) when tuple_size(ip) == 4, do: 32
  defp bits(ip) when tuple_size(ip) == 8, do: 128

  defp mask(ip, prefix) do
    size = bits(ip)
    host_bits = size - prefix
    <<network::size(^prefix), _::size(^host_bits)>> = to_binary(ip)
    from_binary(<<network::size(prefix), 0::size(host_bits)>>)
  end

  defp to_binary({a, b, c, d}), do: <<a, b, c, d>>

  defp to_binary({a, b, c, d, e, f, g, h}),
    do: <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>

  defp from_binary(<<a, b, c, d>>), do: {a, b, c, d}

  defp from_binary(<<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>>),
    do: {a, b, c, d, e, f, g, h}
end
