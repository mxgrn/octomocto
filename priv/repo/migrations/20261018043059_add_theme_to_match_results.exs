defmodule Octomocto.Repo.Migrations.AddThemeToMatchResults do
  use Ecto.Migration

  def change do
    # The theme of the field, to see which themes are popular.
    # Nil for the results from before the theme.
    alter table(:match_results) do
      add :theme, :string
    end
  end
end
