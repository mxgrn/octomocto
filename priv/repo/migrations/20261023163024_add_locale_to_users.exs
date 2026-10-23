defmodule Octomocto.Repo.Migrations.AddLocaleToUsers do
  use Ecto.Migration

  def change do
    # The first language of the browser, the same as `guests.locale`
    alter table(:users) do
      add :locale, :string
    end
  end
end
