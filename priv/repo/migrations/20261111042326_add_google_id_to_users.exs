defmodule Octomocto.Repo.Migrations.AddGoogleIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # The "sub" claim of the Google ID token
      add :google_id, :string
    end

    create unique_index(:users, [:google_id])
  end
end
