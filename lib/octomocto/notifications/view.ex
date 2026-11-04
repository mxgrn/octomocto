defmodule Octomocto.Notifications.View do
  @moduledoc """
  A user or a guest saw a notification. The `inserted_at` is the first
  time. The `closed_at` is the time when the user or guest closed it, or
  nil. Each view has a `user_id` or a `guest_id`, never both.
  """
  use Ecto.Schema

  schema "notification_views" do
    belongs_to :notification, Octomocto.Notifications.Notification
    field :user_id, :id
    field :guest_id, :binary_id
    field :closed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
