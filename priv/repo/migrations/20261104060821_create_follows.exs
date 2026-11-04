defmodule Octomocto.Repo.Migrations.CreateFollows do
  use Ecto.Migration

  def change do
    # One row is a follow. Two users who follow each other are friends.
    create table(:follows) do
      add :follower_id, references(:users, on_delete: :delete_all), null: false
      add :followed_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:follows, [:follower_id, :followed_id])
    create index(:follows, [:followed_id])
    create constraint(:follows, :not_self, check: "follower_id <> followed_id")
  end
end
