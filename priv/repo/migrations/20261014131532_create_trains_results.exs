defmodule Octomocto.Repo.Migrations.CreateTrainsResults do
  use Ecto.Migration

  def change do
    # One row for each player of a finished round
    create table(:trains_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:trains_results, [:game_id])
    create index(:trains_results, [:user_id])
    create index(:trains_results, [:settings])
  end
end
