defmodule Octomocto.Repo.Migrations.AddLogToBlocklistEntries do
  use Ecto.Migration

  import EctoEnumMigration

  def change do
    create_type(:blocklist_log, [:quiet, :log])

    # :log when the blocked requests of the entry write a line in the log
    alter table(:blocklist_entries) do
      add :log, :blocklist_log, null: false, default: "quiet"
    end
  end
end
