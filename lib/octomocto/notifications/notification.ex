defmodule Octomocto.Notifications.Notification do
  @moduledoc """
  A notification to the user `user_id`. The `actor` is the user who did
  the thing. The text comes from the `kind` when a page shows it (see
  `Octomocto.Notifications`).
  """
  use Ecto.Schema

  schema "notifications" do
    field :user_id, :id
    field :kind, Ecto.Enum, values: [:followed]
    belongs_to :actor, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
