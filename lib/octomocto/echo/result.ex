defmodule Octomocto.Echo.Result do
  @moduledoc """
  The result of one player in one finished Echo game. All rows of a game
  have the same `game_id` and `settings`. The `settings` tell which results
  can be compared, for example `%{"pads" => 6, "players" => 1}`. The
  `score` is the length of the longest sequence that the player repeated.
  """
  use Ecto.Schema

  schema "echo_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
