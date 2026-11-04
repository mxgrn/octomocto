defmodule Octomocto.Repo.Migrations.CreateNotificationCloses do
  use Ecto.Migration

  def change do
    # One row for each user or guest that closed a notification. The
    # `inserted_at` is the time of the first close.
    create table(:notification_closes) do
      add :notification_id, references(:notifications, on_delete: :delete_all), null: false
      # Nil for a guest
      add :user_id, references(:users, on_delete: :delete_all)
      # Nil for a user
      add :guest_id, references(:guests, type: :uuid, on_delete: :delete_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create unique_index(:notification_closes, [:notification_id, :user_id],
             where: "user_id IS NOT NULL"
           )

    create unique_index(:notification_closes, [:notification_id, :guest_id],
             where: "guest_id IS NOT NULL"
           )

    create index(:notification_closes, [:user_id])
    create index(:notification_closes, [:guest_id])

    create constraint(:notification_closes, :user_or_guest,
             check: "(user_id IS NULL) <> (guest_id IS NULL)"
           )
  end
end
