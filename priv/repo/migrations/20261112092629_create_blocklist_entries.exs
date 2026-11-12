defmodule Octomocto.Repo.Migrations.CreateBlocklistEntries do
  use Ecto.Migration

  def change do
    create table(:blocklist_entries) do
      # An IP or a CIDR range, in normal text
      add :ip, :string
      # A part of the User-Agent header. Text, because a full header can be
      # longer than 255 characters.
      add :user_agent, :text
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    # One entry for each IP and user agent. Null is the same as null here.
    create unique_index(
             :blocklist_entries,
             ["coalesce(ip, '')", "coalesce(lower(user_agent), '')"],
             name: :blocklist_entries_ip_user_agent_index
           )
  end
end
