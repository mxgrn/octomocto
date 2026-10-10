defmodule Octomocto.Repo.Migrations.AddModeToSchulteResultSettings do
  use Ecto.Migration

  # All results before the modes were added are from the easy mode
  def up do
    execute """
    UPDATE schulte_results
    SET settings = settings || '{"mode": "easy"}'
    WHERE NOT settings ? 'mode'
    """
  end

  def down do
    execute "UPDATE schulte_results SET settings = settings - 'mode'"
  end
end
