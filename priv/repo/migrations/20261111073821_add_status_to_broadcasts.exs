defmodule Octomocto.Repo.Migrations.AddStatusToBroadcasts do
  use Ecto.Migration

  import EctoEnumMigration

  def change do
    create_type(:broadcast_status, [:test, :sent])

    # A test broadcast goes only to the admins. The old ones were sent to all.
    alter table(:broadcasts) do
      add :status, :broadcast_status, null: false, default: "sent"
    end
  end
end
