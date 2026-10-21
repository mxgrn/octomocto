defmodule Octomocto.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications) do
      # Markdown, on one line
      add :text, :text, null: false
      # The id of a game in `OctomoctoWeb.HomeLive.games/0`. Nil means all pages.
      add :game, :string
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:expires_at])
  end
end
