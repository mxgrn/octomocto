defmodule Octomocto.Repo.Migrations.CreateGameRatings do
  use Ecto.Migration

  def change do
    create table(:game_ratings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :game, :string, null: false
      add :stars, :integer, null: false
      add :comment, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:game_ratings, [:user_id, :game])
  end
end
