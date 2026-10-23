defmodule Octomocto.Guests.Guest do
  @moduledoc """
  A guest that finished a game. The `id` is the guest id in the session
  (see `OctomoctoWeb.GuestName`). The `name` is the guest name when the
  guest first finished a game, as text: a later change of the word lists
  in `Octomocto.GuestName` does not change it.

  Use a guest only for statistics and for the names in the results. Never
  use it for authentication or access: a guest is not a user. Guest names
  are not unique.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}

  schema "guests" do
    field :name, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
