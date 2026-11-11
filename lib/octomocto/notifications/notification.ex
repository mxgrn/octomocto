defmodule Octomocto.Notifications.Notification do
  @moduledoc """
  A notification to the user `user_id`. The `actor` is the user who did
  the thing. The text comes from the `kind` when a page shows it (see
  `Octomocto.Notifications`).

  The kinds:

    * `:followed`: the actor follows the user.
    * `:lost_top`: the actor took the first place of the user in the Best
      results of the `game` with the `settings` of the results.
  """
  use Ecto.Schema

  schema "notifications" do
    field :user_id, :id
    field :kind, Ecto.Enum, values: [:followed, :lost_top]
    field :game, :string
    field :settings, :map
    belongs_to :actor, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
