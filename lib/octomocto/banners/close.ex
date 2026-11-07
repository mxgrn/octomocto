defmodule Octomocto.Banners.Close do
  @moduledoc """
  A user or a guest closed a banner. The `inserted_at` is the time of
  the first close. Each close has a `user_id` or a `guest_id`, never both.
  """
  use Ecto.Schema

  schema "banner_closes" do
    belongs_to :banner, Octomocto.Banners.Banner
    field :user_id, :id
    field :guest_id, :binary_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
