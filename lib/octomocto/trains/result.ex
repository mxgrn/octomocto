defmodule Octomocto.Trains.Result do
  @moduledoc """
  The result of one player in one finished trains round. All rows of a
  round have the same `game_id`, `settings` and `score`, because the
  players play together. The `settings` tell which results can be
  compared, for example `%{"switch_count" => 6, "trains_per_house" => 2,
  "pace" => "normal", "players" => 2}`. The `score` is the number of
  trains that got to the correct house.
  """
  use Ecto.Schema

  schema "trains_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
