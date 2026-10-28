defmodule Octomocto.Snap.Result do
  @moduledoc """
  The result of one finished Snap round. The `settings` tell which results
  can be compared, for example `%{"back" => 1, "players" => 1}`. The
  `score` has the multipliers in it. The `correct` and `wrong` answers give
  the accuracy.
  """
  use Ecto.Schema

  schema "snap_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :correct, :integer
    field :wrong, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
