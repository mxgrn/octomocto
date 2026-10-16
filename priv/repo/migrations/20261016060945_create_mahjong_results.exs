defmodule Octomocto.Repo.Migrations.CreateMahjongResults do
  use Ecto.Migration

  def change do
    # One row for each player of a cleared board
    create table(:mahjong_results) do
      add :game_id, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :nilify_all)
      add :settings, :map, null: false
      add :score, :integer, null: false
      add :elapsed_ms, :integer, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:mahjong_results, [:game_id])
    create index(:mahjong_results, [:user_id])
    create index(:mahjong_results, [:settings])
  end
end
