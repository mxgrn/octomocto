defmodule Octomocto.Repo.Migrations.CreateSnapResults do
  use Ecto.Migration

  def change do
    # One row for each finished round
    create table(:snap_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      # Nil for a user
      add :guest_id, references(:guests, type: :uuid, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      add :correct, :integer, null: false
      add :wrong, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:snap_results, [:game_id])
    create index(:snap_results, [:user_id])
    create index(:snap_results, [:guest_id])
    create index(:snap_results, [:settings])
  end
end
