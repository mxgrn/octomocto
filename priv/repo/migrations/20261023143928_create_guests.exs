defmodule Octomocto.Repo.Migrations.CreateGuests do
  use Ecto.Migration

  @results ~w(schulte_results trains_results match_results set_results sudoku_results
              echo_results mahjong_results overlap_results)a

  def change do
    # One row for each guest that finished a game. The id is the guest id
    # in the session (see `OctomoctoWeb.GuestName`).
    create table(:guests, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    for table <- @results do
      # Nil for a user, and for a guest from before the guests table
      alter table(table) do
        add :guest_id, references(:guests, type: :uuid, on_delete: :nilify_all)
      end

      create index(table, [:guest_id])
    end
  end
end
