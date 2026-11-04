defmodule Octomocto.Repo.Migrations.RenameSchulteToNimbleMosaic do
  use Ecto.Migration

  # The game with 90 shapes was "Schulte" and is now "Nimble Mosaic". The
  # name "Schulte" is for the classic Schulte tables later.
  @renames [
    {"INDEX", "schulte_results_pkey", "nimble_mosaic_results_pkey"},
    {"INDEX", "schulte_results_game_id_index", "nimble_mosaic_results_game_id_index"},
    {"INDEX", "schulte_results_guest_id_index", "nimble_mosaic_results_guest_id_index"},
    {"INDEX", "schulte_results_settings_index", "nimble_mosaic_results_settings_index"},
    {"INDEX", "schulte_results_user_id_index", "nimble_mosaic_results_user_id_index"},
    {"SEQUENCE", "schulte_results_id_seq", "nimble_mosaic_results_id_seq"}
  ]

  @constraints [
    {"schulte_results_guest_id_fkey", "nimble_mosaic_results_guest_id_fkey"},
    {"schulte_results_user_id_fkey", "nimble_mosaic_results_user_id_fkey"}
  ]

  def up do
    rename table(:schulte_results), to: table(:nimble_mosaic_results)

    for {kind, from, to} <- @renames, do: execute("ALTER #{kind} #{from} RENAME TO #{to}")

    for {from, to} <- @constraints,
        do: execute("ALTER TABLE nimble_mosaic_results RENAME CONSTRAINT #{from} TO #{to}")

    # The saved settings and the notifications keep the game id
    execute "UPDATE settings SET game = 'nimble-mosaic' WHERE game = 'schulte'"
    execute "UPDATE notifications SET game = 'nimble-mosaic' WHERE game = 'schulte'"
  end

  def down do
    execute "UPDATE notifications SET game = 'schulte' WHERE game = 'nimble-mosaic'"
    execute "UPDATE settings SET game = 'schulte' WHERE game = 'nimble-mosaic'"

    for {from, to} <- @constraints,
        do: execute("ALTER TABLE nimble_mosaic_results RENAME CONSTRAINT #{to} TO #{from}")

    for {kind, from, to} <- @renames, do: execute("ALTER #{kind} #{to} RENAME TO #{from}")

    rename table(:nimble_mosaic_results), to: table(:schulte_results)
  end
end
