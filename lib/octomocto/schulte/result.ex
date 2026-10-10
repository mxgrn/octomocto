defmodule Octomocto.Schulte.Result do
  @moduledoc """
  The result of one player in one finished field. All rows of a field have
  the same `game_id`, `settings` and `elapsed_ms`. The `settings` tell which
  results can be compared, for example
  `%{"type" => "classic", "mode" => "easy", "players" => 2}`.
  """
  use Ecto.Schema

  schema "schulte_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
