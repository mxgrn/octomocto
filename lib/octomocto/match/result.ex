defmodule Octomocto.Match.Result do
  @moduledoc """
  The result of one player in one finished Match field. All rows of a field
  have the same `game_id`, `settings` and `elapsed_ms`. The `settings` tell
  which results can be compared, for example
  `%{"set" => 2, "cards" => 16, "players" => 1}`. The theme is not in the
  settings: it does not change how hard the game is.
  """
  use Ecto.Schema

  schema "match_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
