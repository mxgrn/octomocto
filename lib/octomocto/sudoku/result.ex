defmodule Octomocto.Sudoku.Result do
  @moduledoc """
  The result of one player in one solved sudoku. All rows of a puzzle have
  the same `game_id`, `settings` and `elapsed_ms`. The `settings` tell
  which results can be compared, for example
  `%{"difficulty" => "easy", "players" => 1}`. The `score` is the number of
  cells that the player filled.
  """
  use Ecto.Schema

  schema "sudoku_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
