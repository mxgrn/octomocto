defmodule Octomocto.Ratings.Rating do
  @moduledoc """
  The vote of one user for one game: 1 to 5 `stars`, and an optional
  `comment` for 1 to 4 stars. The `game` is the game id of the front page,
  for example "memory". `inserted_at` is the date of the vote.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "game_ratings" do
    field :user_id, :id
    field :game, :string
    field :stars, :integer
    field :comment, :string

    timestamps(type: :utc_datetime)
  end

  @comment_length 2000

  def vote_changeset(rating, attrs) do
    rating
    |> cast(attrs, [:stars])
    |> validate_required([:stars])
    |> validate_inclusion(:stars, 1..5)
    |> unique_constraint([:user_id, :game])
  end

  def comment_changeset(rating, attrs) do
    rating
    |> cast(attrs, [:comment])
    |> validate_required([:comment])
    |> validate_length(:comment, max: @comment_length)
  end
end
