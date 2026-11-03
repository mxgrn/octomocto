defmodule Octomocto.Repo.Migrations.CreateSettings do
  use Ecto.Migration

  def change do
    # The settings that a user or a guest chose last, one row for each game
    create table(:settings) do
      add :game, :string, null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :delete_all)
      # Nil for a user. No reference: a guest is in `guests` only after a
      # finished game.
      add :guest_id, :uuid
      add :settings, :map, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:settings, [:user_id, :game], where: "user_id IS NOT NULL")
    create unique_index(:settings, [:guest_id, :game], where: "guest_id IS NOT NULL")

    create constraint(:settings, :user_or_guest, check: "(user_id IS NULL) <> (guest_id IS NULL)")
  end
end
