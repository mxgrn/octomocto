defmodule Octomocto.Banners.Banner do
  @moduledoc """
  A message on one line in a bar above the header, until it expires or the
  user closes it. See `Octomocto.Banners`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "banners" do
    # Markdown, on one line
    field :text, :string
    # The id of a game in `OctomoctoWeb.HomeLive.games/0`. Nil means all pages.
    field :game, :string
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(banner, attrs) do
    banner
    |> cast(attrs, [:text, :game, :expires_at])
    |> validate_required([:text, :expires_at])
    |> validate_format(:text, ~r/\A[^\r\n]*\z/, message: "must be on one line")
    |> validate_inclusion(:game, Enum.map(OctomoctoWeb.HomeLive.games(), & &1.id))
  end
end
