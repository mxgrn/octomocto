defmodule Octomocto.Repo.Migrations.AddPerksToGrazeResultSettings do
  use Ecto.Migration

  # The perk squares came on 2026-11-11 at 12:15 UTC. The results (and the
  # notifications about the Best results) before that time are without
  # perks, the later ones with perks.
  @perks_at "'2026-11-11 12:15:00'"

  def up do
    execute """
    UPDATE graze_results
    SET settings = settings || jsonb_build_object('perks', inserted_at >= #{@perks_at})
    WHERE NOT settings ? 'perks'
    """

    execute """
    UPDATE notifications
    SET settings = settings || jsonb_build_object('perks', inserted_at >= #{@perks_at})
    WHERE game = 'graze' AND NOT settings ? 'perks'
    """
  end

  def down do
    execute "UPDATE graze_results SET settings = settings - 'perks'"
    execute "UPDATE notifications SET settings = settings - 'perks' WHERE game = 'graze'"
  end
end
