defmodule Octomocto.Schulte.Result do
  @moduledoc """
  The result of one player in one finished Schulte table. All rows of a
  table have the same `game_id`, `settings` and `elapsed_ms`. The
  `settings` tell which results can be compared, for example
  `%{"size" => 5, "marks" => false, "players" => 2}`.
  """
  use Ecto.Schema

  schema "schulte_results" do
    field :game_id, :string
    field :settings, :map
    field :score, :integer
    field :elapsed_ms, :integer
    belongs_to :user, Octomocto.Accounts.User
    belongs_to :guest, Octomocto.Guests.Guest, type: :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
