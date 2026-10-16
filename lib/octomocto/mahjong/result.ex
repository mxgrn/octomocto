defmodule Octomocto.Mahjong.Result do
  @moduledoc """
  The result of one player in one cleared mahjong board. All rows of a
  board have the same `game_id`, `settings` and `elapsed_ms`. The
  `settings` tell which results can be compared, for example
  `%{"layout" => "turtle", "players" => 1}`. The `score` is the number of
  pairs that the player removed.
  """
  use Ecto.Schema

  schema "mahjong_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
