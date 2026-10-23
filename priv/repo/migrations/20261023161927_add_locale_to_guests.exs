defmodule Octomocto.Repo.Migrations.AddLocaleToGuests do
  use Ecto.Migration

  def change do
    # The first language of the browser (`Accept-Language`), for example
    # "pt-BR". Nil when the browser does not send it.
    alter table(:guests) do
      add :locale, :string
    end
  end
end
