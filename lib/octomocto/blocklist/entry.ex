defmodule Octomocto.Blocklist.Entry do
  @moduledoc """
  One rule of the blocklist: an IP or CIDR range, a part of the user agent,
  or both. See `Octomocto.Blocklist`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Octomocto.IpRange

  # Normal browsers of today. A user agent rule without an IP must not match
  # them, because it would block real players.
  @browsers [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:132.0) Gecko/20100101 Firefox/132.0",
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 Edg/130.0.0.0"
  ]

  # The parts of a browser user agent. A rule without an IP must not have
  # them: a full user agent from the traffic page has them, and it can be
  # the user agent of real players.
  @browser_parts ~w(mozilla/ applewebkit/ chrome/ safari/ firefox/ gecko/ edg/ opr/)

  schema "blocklist_entries" do
    field :ip, :string
    field :user_agent, :string
    field :note, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:ip, :user_agent, :note])
    |> validate_length(:user_agent, min: 4, max: 300)
    |> validate_length(:note, max: 255)
    |> normalize_ip()
    |> validate_ip_or_user_agent()
    |> validate_user_agent()
    |> unique_constraint(:ip,
      name: :blocklist_entries_ip_user_agent_index,
      message: "is already blocked"
    )
  end

  defp normalize_ip(changeset) do
    case get_change(changeset, :ip) do
      nil ->
        changeset

      text ->
        case IpRange.parse(text) do
          {:ok, range} -> put_change(changeset, :ip, IpRange.to_string(range))
          :error -> add_error(changeset, :ip, "is not an IP or a CIDR range")
        end
    end
  end

  defp validate_ip_or_user_agent(changeset) do
    if get_field(changeset, :ip) || get_field(changeset, :user_agent),
      do: changeset,
      else: add_error(changeset, :ip, "set an IP, a user agent, or both")
  end

  defp validate_user_agent(changeset) do
    user_agent = get_field(changeset, :user_agent)

    if user_agent && is_nil(get_field(changeset, :ip)) && browser?(user_agent),
      do:
        add_error(
          changeset,
          :user_agent,
          "matches normal browsers; keep only the bot name, or add an IP"
        ),
      else: changeset
  end

  defp browser?(user_agent) do
    Enum.any?(@browsers, &matches_user_agent?(user_agent, &1)) or
      String.contains?(String.downcase(user_agent), @browser_parts)
  end

  @doc """
  Gives true when the `pattern` is in the `user_agent` header. Upper and
  lower case are the same.
  """
  def matches_user_agent?(_pattern, nil), do: false

  def matches_user_agent?(pattern, user_agent),
    do: String.contains?(String.downcase(user_agent), String.downcase(pattern))
end
