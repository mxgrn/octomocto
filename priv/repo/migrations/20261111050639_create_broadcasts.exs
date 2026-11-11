defmodule Octomocto.Repo.Migrations.CreateBroadcasts do
  use Ecto.Migration

  def change do
    # The notifications from the admins to all users and guests (see
    # `Octomocto.Notifications`)
    create table(:broadcasts) do
      # Markdown, on one line
      add :text, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:broadcasts, [:inserted_at])
  end
end
