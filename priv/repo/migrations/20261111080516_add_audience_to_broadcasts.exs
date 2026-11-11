defmodule Octomocto.Repo.Migrations.AddAudienceToBroadcasts do
  use Ecto.Migration

  import EctoEnumMigration

  def change do
    create_type(:broadcast_audience, [:all, :users, :guests])

    # The readers of a sent broadcast. The old ones went to all.
    alter table(:broadcasts) do
      add :audience, :broadcast_audience, null: false, default: "all"
    end
  end
end
