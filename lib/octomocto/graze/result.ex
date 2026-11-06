defmodule Octomocto.Graze.Result do
  @moduledoc """
  The result of one player in one finished Graze field: the `score` (the
  food squares that the player ate) and the time that the circle of the
  player was in the field (`elapsed_ms`). All rows of a field have the
  same `game_id` and `settings`. The `settings` tell which results can be
  compared, for example `%{"players" => 2}`.
  """
  use Ecto.Schema

  schema "graze_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
