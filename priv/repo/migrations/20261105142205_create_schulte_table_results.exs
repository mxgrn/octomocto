defmodule Octomocto.Repo.Migrations.CreateSchulteTableResults do
  use Ecto.Migration

  # The results of the classic Schulte tables. The old "schulte_results"
  # table of the game with 90 shapes is now "nimble_mosaic_results".
  def change do
    # One row for each player of a finished table
    create table(:schulte_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      # Nil for a user
      add :guest_id, references(:guests, type: :uuid, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      add :elapsed_ms, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:schulte_results, [:game_id])
    create index(:schulte_results, [:user_id])
    create index(:schulte_results, [:guest_id])
    create index(:schulte_results, [:settings])
  end
end
