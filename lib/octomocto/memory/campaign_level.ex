defmodule Octomocto.Memory.CampaignLevel do
  @moduledoc """
  The best run of a user on one level of the Memory campaign (see
  `Octomocto.Memory.Campaign`). The `best_cleared` cards are the most cards
  that the user cleared before a slip. The `completed_at` is the time of the
  first run with no slip, nil until then.
  """
  use Ecto.Schema

  schema "memory_campaign_levels" do
    field :level, :integer
    field :best_cleared, :integer
    field :completed_at, :utc_datetime_usec
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end
end
