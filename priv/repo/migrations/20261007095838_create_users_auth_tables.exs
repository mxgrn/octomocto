defmodule Octomocto.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext
      add :confirmed_at, :utc_datetime
      add :telegram_id, :bigint
      add :telegram_username, :string
      add :name, :string
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:telegram_id])

    # A user must be able to sign in with at least one method
    create constraint(:users, :email_or_telegram_id,
             check: "email IS NOT NULL OR telegram_id IS NOT NULL"
           )

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
