defmodule Octomocto.Notifications.Broadcast do
  @moduledoc """
  A notification from the admins to all users and guests, for example
  about a new game. Each reader gets only the broadcasts from after the
  signup, or after the first visit of a guest (see `Octomocto.Notifications`).
  A test broadcast goes only to the admins.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "broadcasts" do
    # Markdown, on one line, in English
    field :text, :string
    # A test broadcast goes only to the admins (see `Octomocto.Notifications`)
    field :status, Ecto.Enum, values: [:test, :sent], default: :sent
    # The readers when it is sent. A test goes to the admins for all audiences.
    field :audience, Ecto.Enum, values: [:all, :users, :guests], default: :all

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(broadcast, attrs) do
    broadcast
    |> cast(attrs, [:audience])
    |> validate_required([:audience])
    |> text_changeset(attrs)
  end

  @doc "Changes only the text, for a broadcast that was sent."
  def text_changeset(broadcast, attrs) do
    broadcast
    |> cast(attrs, [:text])
    |> validate_required([:text])
    |> validate_format(:text, ~r/\A[^\r\n]*\z/, message: "must be on one line")
  end
end
