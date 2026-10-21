defmodule Octomocto.Repo.Migrations.CreateMemoryCampaignLevels do
  use Ecto.Migration

  def change do
    # The best run of a user on one level of the Memory campaign
    create table(:memory_campaign_levels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :level, :integer, null: false
      # The most cards that the user cleared before a slip
      add :best_cleared, :integer, null: false
      # The time of the first run with no slip, nil until then
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:memory_campaign_levels, [:user_id, :level])
    create index(:memory_campaign_levels, [:level, :completed_at])
  end
end
