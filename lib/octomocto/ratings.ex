defmodule Octomocto.Ratings do
  @moduledoc """
  The star votes of the players for each game. The result screen of a game
  shows the card (`octo-rating` in `assets/js/rating.js`) to a signed-in
  user who played the game 5 times or more and did not vote for it yet.
  A user votes once for each game. Only for the games in `games/0`.
  """
  import Ecto.Query

  alias Octomocto.Ratings.Rating
  alias Octomocto.{Repo, Stats}

  @games ["memory", "trains"]

  # The number of games of a game before the card shows
  @games_before 5

  @doc "The games that show the card."
  def games, do: @games

  @doc """
  True when the result screen of the `game` shows the card to the user:
  a signed-in user, with 5 games of this game or more, and no vote for it.
  """
  def show?(nil, _game), do: false

  def show?(user_id, game) when game in @games do
    not voted?(user_id, game) and Stats.games_of(:user_id, user_id, game) >= @games_before
  end

  def show?(_user_id, _game), do: false

  @doc """
  Saves the vote of the user for the `game`. Gives `{:error, :not_allowed}`
  when the card does not show to the user (see `show?/2`).
  """
  def vote(user_id, game, stars) do
    if show?(user_id, game) do
      %Rating{user_id: user_id, game: game}
      |> Rating.vote_changeset(%{stars: stars})
      |> Repo.insert()
    else
      {:error, :not_allowed}
    end
  end

  @doc """
  Adds the comment to the vote of the user for the `game`. Only for a vote
  of 1 to 4 stars with no comment yet, else `{:error, :not_allowed}`.
  """
  def comment(user_id, game, text) when is_binary(text) do
    rating =
      Repo.one(
        from r in Rating,
          where: r.user_id == ^user_id and r.game == ^game and r.stars < 5 and is_nil(r.comment)
      )

    if rating do
      rating
      |> Rating.comment_changeset(%{comment: String.trim(text)})
      |> Repo.update()
    else
      {:error, :not_allowed}
    end
  end

  defp voted?(user_id, game),
    do: Repo.exists?(from r in Rating, where: r.user_id == ^user_id and r.game == ^game)
end
