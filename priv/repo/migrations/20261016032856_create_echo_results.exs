defmodule Octomocto.Repo.Migrations.CreateEchoResults do
  use Ecto.Migration

  def change do
    # One row for each player of a finished game
    create table(:echo_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:echo_results, [:game_id])
    create index(:echo_results, [:user_id])
    create index(:echo_results, [:settings])
  end
end
