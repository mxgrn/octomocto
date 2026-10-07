defmodule Octomocto.Repo.Migrations.CreateSchulteResults do
  use Ecto.Migration

  def change do
    # One row for each player of a finished field
    create table(:schulte_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      add :elapsed_ms, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:schulte_results, [:game_id])
    create index(:schulte_results, [:user_id])
    create index(:schulte_results, [:settings])
  end
end
