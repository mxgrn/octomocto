defmodule Octomocto.Friends.Follow do
  @moduledoc """
  The `follower_id` user follows the `followed_id` user. Two users who
  follow each other are friends (see `Octomocto.Friends`).
  """
  use Ecto.Schema

  schema "follows" do
    field :follower_id, :id
    field :followed_id, :id

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
