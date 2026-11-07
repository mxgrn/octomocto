defmodule Octomocto.Repo.Migrations.AddPreferredLocaleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # The language that the user picked in the footer, for example "pt"
      add :preferred_locale, :string
    end
  end
end
