defmodule Octomocto.InkTrail.Result do
  @moduledoc """
  The result of one finished Ink Trail game. The `settings` tell which
  results can be compared, for now always `%{"players" => 1}`. The
  `best_distance` is the largest distance between the two octopi in the
  game, and the `last_distance` is the distance at the end, where the next
  game of the player starts.
  """
  use Ecto.Schema

  schema "ink_trail_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :best_distance, :integer
    field :last_distance, :integer
    field :wrong, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
