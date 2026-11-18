defmodule Octomocto.Repo.Migrations.CopyUserTabsToSettings do
  use Ecto.Migration

  # The last tabs of the Memory and Trains pages move from the users to the
  # "tab" key of the saved settings (see `Octomocto.GameSettings`). A tab
  # that is already in the settings stays. The columns of the users stay
  # for now.
  def up do
    for {game, column} <- [{"memory", "memory_tab"}, {"trains", "trains_tab"}] do
      execute("""
      INSERT INTO settings (user_id, game, settings, inserted_at, updated_at)
      SELECT id, '#{game}', jsonb_build_object('tab', #{column}), now(), now()
      FROM users
      WHERE #{column} IS NOT NULL
      ON CONFLICT (user_id, game) WHERE user_id IS NOT NULL
      DO UPDATE SET settings = EXCLUDED.settings || settings.settings
      """)
    end
  end

  # The old columns still have the tabs
  def down, do: :ok
end
