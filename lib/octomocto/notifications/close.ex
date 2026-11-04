defmodule Octomocto.Notifications.Close do
  @moduledoc """
  A user or a guest closed a notification. The `inserted_at` is the time of
  the first close. Each close has a `user_id` or a `guest_id`, never both.
  """
  use Ecto.Schema

  schema "notification_closes" do
    belongs_to :notification, Octomocto.Notifications.Notification
    field :user_id, :id
    field :guest_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
