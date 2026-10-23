defmodule Octomocto.SetGame.Result do
  @moduledoc """
  The result of one player in one finished Set table. All rows of a table
  have the same `game_id`, `settings` and `elapsed_ms`. The `settings` tell
  which results can be compared, for example
  `%{"mode" => "normal", "players" => 1}`. The `score` is the number of
  sets that the player found.
  """
  use Ecto.Schema

  schema "set_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
