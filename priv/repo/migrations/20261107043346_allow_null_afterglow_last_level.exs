defmodule Octomocto.Repo.Migrations.AllowNullAfterglowLastLevel do
  use Ecto.Migration

  # A game with turns has no rounds, so it has no last round
  def change do
    alter table(:afterglow_results) do
      modify :last_level, :integer, null: true, from: {:integer, null: false}
    end
  end
end
