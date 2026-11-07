defmodule Octomocto.Repo.Migrations.RenameNotificationsToBanners do
  use Ecto.Migration

  # The bar above the header is now "banners". The word "notifications" is
  # for the inbox of each user. The indexes, keys and sequences get the
  # names that Ecto would give to the new tables.
  @renames [
    {"TABLE", "notifications", "banners"},
    {"TABLE", "notification_closes", "banner_closes"},
    {"SEQUENCE", "notifications_id_seq", "banners_id_seq"},
    {"SEQUENCE", "notification_closes_id_seq", "banner_closes_id_seq"},
    {"INDEX", "notifications_pkey", "banners_pkey"},
    {"INDEX", "notification_closes_pkey", "banner_closes_pkey"},
    {"INDEX", "notifications_expires_at_index", "banners_expires_at_index"},
    {"INDEX", "notification_closes_notification_id_user_id_index",
     "banner_closes_banner_id_user_id_index"},
    {"INDEX", "notification_closes_notification_id_guest_id_index",
     "banner_closes_banner_id_guest_id_index"},
    {"INDEX", "notification_closes_user_id_index", "banner_closes_user_id_index"},
    {"INDEX", "notification_closes_guest_id_index", "banner_closes_guest_id_index"}
  ]

  @fkeys [
    {"notification_closes_notification_id_fkey", "banner_closes_banner_id_fkey"},
    {"notification_closes_user_id_fkey", "banner_closes_user_id_fkey"},
    {"notification_closes_guest_id_fkey", "banner_closes_guest_id_fkey"}
  ]

  def up do
    for {kind, from, to} <- @renames, do: execute("ALTER #{kind} #{from} RENAME TO #{to}")
    execute "ALTER TABLE banner_closes RENAME COLUMN notification_id TO banner_id"

    for {from, to} <- @fkeys,
        do: execute("ALTER TABLE banner_closes RENAME CONSTRAINT #{from} TO #{to}")
  end

  def down do
    for {from, to} <- @fkeys,
        do: execute("ALTER TABLE banner_closes RENAME CONSTRAINT #{to} TO #{from}")

    execute "ALTER TABLE banner_closes RENAME COLUMN banner_id TO notification_id"

    for {kind, from, to} <- Enum.reverse(@renames),
        do: execute("ALTER #{kind} #{to} RENAME TO #{from}")
  end
end
