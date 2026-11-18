defmodule Octomocto.Repo.Migrations.RemoveTabsFromUsers do
  use Ecto.Migration

  # The last tabs are in the saved settings now (see
  # `CopyUserTabsToSettings`). A rollback adds the columns again, but
  # without the tabs.
  def change do
    alter table(:users) do
      remove :memory_tab, :string
      remove :trains_tab, :string
    end
  end
end
