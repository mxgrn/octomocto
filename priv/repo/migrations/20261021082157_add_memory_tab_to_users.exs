defmodule Octomocto.Repo.Migrations.AddMemoryTabToUsers do
  use Ecto.Migration

  def change do
    # The tab of the Memory page that the user used last: "free" or
    # "campaign". Nil means Free play.
    alter table(:users) do
      add :memory_tab, :string
    end
  end
end
