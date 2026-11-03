defmodule Octomocto.GameSettings.Saved do
  @moduledoc """
  The settings that a user or a guest chose last on the settings page of
  a game (see `Octomocto.GameSettings`). The `game` is the name of the
  game, for example "memory". The `settings` are the params of the
  settings page, for example `%{"players" => "2", "cards" => "16"}`.
  Only one of `user_id` and `guest_id` is set.
  """
  use Ecto.Schema

  schema "settings" do
    field :game, :string
    field :guest_id, :binary_id
    field :settings, :map
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end
end
