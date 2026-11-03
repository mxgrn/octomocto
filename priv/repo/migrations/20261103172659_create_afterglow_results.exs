defmodule Octomocto.Repo.Migrations.CreateAfterglowResults do
  use Ecto.Migration

  def change do
    # One row for each finished game
    create table(:afterglow_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      # Nil for a user
      add :guest_id, references(:guests, type: :uuid, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      # The most tiles of a fully correct round, nil when no round was correct
      add :best_level, :integer
      # The tiles of the last round: the next game starts with them
      add :last_level, :integer, null: false
      # The fully correct rounds
      add :perfect, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:afterglow_results, [:game_id])
    create index(:afterglow_results, [:user_id])
    create index(:afterglow_results, [:guest_id])
    create index(:afterglow_results, [:settings])
  end
end
