defmodule Octomocto.Repo.Migrations.CreateTrainsCampaignLevels do
  use Ecto.Migration

  def change do
    # The best round of a user on one level of the Trains campaign
    create table(:trains_campaign_levels) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :level, :integer, null: false
      # The most trains that got home in one round of the level
      add :best_correct, :integer, null: false
      # The time of the first round that passed the level, nil until then
      add :completed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:trains_campaign_levels, [:user_id, :level])
    create index(:trains_campaign_levels, [:level, :completed_at])
  end
end
