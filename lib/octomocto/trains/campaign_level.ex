defmodule Octomocto.Trains.CampaignLevel do
  @moduledoc """
  The best round of a user on one level of the Trains campaign (see
  `Octomocto.Trains.Campaign`). The `best_correct` trains are the most
  trains that got home in one round. The `completed_at` is the time of the
  first round that passed the level, nil until then.
  """
  use Ecto.Schema

  schema "trains_campaign_levels" do
    field :level, :integer
    field :best_correct, :integer
    field :completed_at, :utc_datetime_usec
    belongs_to :user, Octomocto.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end
end
