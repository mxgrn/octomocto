defmodule Octomocto.Repo.Migrations.CreateInkTrailResults do
  use Ecto.Migration

  def change do
    # One row for each finished game
    create table(:ink_trail_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      # Nil for a user
      add :guest_id, references(:guests, type: :uuid, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      # The largest distance between the two octopi in the game
      add :best_distance, :integer, null: false
      # The distance at the end: the next game starts with it
      add :last_distance, :integer, null: false
      # The wrong taps
      add :wrong, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:ink_trail_results, [:game_id])
    create index(:ink_trail_results, [:user_id])
    create index(:ink_trail_results, [:guest_id])
    create index(:ink_trail_results, [:settings])
  end
end
