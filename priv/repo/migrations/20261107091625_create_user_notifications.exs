defmodule Octomocto.Repo.Migrations.CreateUserNotifications do
  use Ecto.Migration

  def change do
    # The inbox of each user (see `Octomocto.Notifications`). The old table
    # with this name is now `banners`.
    create table(:notifications) do
      # The recipient
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      # The user who did the thing, for example the follower
      add :actor_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    # One notification for each kind and actor: a second follow from the
    # same user does not add a row
    create unique_index(:notifications, [:user_id, :kind, :actor_id])
    create index(:notifications, [:actor_id])

    # The notifications after this time are unread
    alter table(:users) do
      add :notifications_seen_at, :utc_datetime_usec
    end
  end
end
