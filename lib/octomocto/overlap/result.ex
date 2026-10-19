defmodule Octomocto.Overlap.Result do
  @moduledoc """
  The result of one player in one finished Overlap deck. All rows of a deck
  have the same `game_id`, `settings` and `elapsed_ms`. The `settings` tell
  which results can be compared, for example
  `%{"symbols" => 8, "players" => 1}`. The `score` is the number of cards
  that the player won.
  """
  use Ecto.Schema

  schema "overlap_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
