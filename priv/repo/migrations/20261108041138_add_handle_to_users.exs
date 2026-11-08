defmodule Octomocto.Repo.Migrations.AddHandleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :handle, :string
    end

    create unique_index(:users, [:handle])
  end
end
