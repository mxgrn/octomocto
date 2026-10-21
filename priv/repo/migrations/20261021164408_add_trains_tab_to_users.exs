defmodule Octomocto.Repo.Migrations.AddTrainsTabToUsers do
  use Ecto.Migration

  def change do
    # The tab of the Trains page that the user used last: "free" or
    # "campaign". Nil means Free play.
    alter table(:users) do
      add :trains_tab, :string
    end
  end
end
