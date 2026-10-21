defmodule Octomocto.Repo.Migrations.AddRoleToUsers do
  use Ecto.Migration

  import EctoEnumMigration

  def change do
    create_type(:user_role, [:user, :admin])

    # Only admins can open the /admin pages
    alter table(:users) do
      add :role, :user_role, null: false, default: "user"
    end
  end
end
