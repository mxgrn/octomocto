defmodule Octomocto.Afterglow.Result do
  @moduledoc """
  The result of one finished Afterglow game. The `settings` tell which
  results can be compared, for example `%{"players" => 1}`. The
  `best_level` is the most tiles of a fully correct round (nil when no
  round was correct), and the `last_level` is the tiles of the last round,
  where the next game of the player starts.
  """
  use Ecto.Schema

  schema "afterglow_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :best_level, :integer
    field :last_level, :integer
    field :perfect, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
