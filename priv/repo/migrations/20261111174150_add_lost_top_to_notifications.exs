defmodule Octomocto.Repo.Migrations.AddLostTopToNotifications do
  use Ecto.Migration

  def change do
    # The game and the settings of the Best results of a lost first place
    # (see `Octomocto.Notifications.lost_top/4`)
    alter table(:notifications) do
      add :game, :string
      add :settings, :map
    end

    # Only one follow notification for each follower. Each lost first place
    # is a new row.
    drop unique_index(:notifications, [:user_id, :kind, :actor_id])

    create unique_index(:notifications, [:user_id, :kind, :actor_id], where: "kind = 'followed'")
  end
end
