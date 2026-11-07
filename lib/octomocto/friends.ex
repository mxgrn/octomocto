defmodule Octomocto.Friends do
  @moduledoc """
  Friends of signed-in users. A user can follow another user (see
  `Octomocto.Friends.Follow`). Two users who follow each other are friends.
  Two users become friends when they finish a game together, and one of
  them came from a link that the other shared.

  The creator of a game (see `Octomocto.Seats`) shares its link. Thus each
  player who joined from that link becomes a friend of the creator. A
  player who came from a list of open games (`from_lobby`) does not, and
  two players who joined do not become friends of each other: they can be
  strangers. Guests have no friends.

  A user can also follow another user from the profile page (see
  `follow/2`). When the other user follows back, they are friends too. The
  front page shows the friends who are online (see `OctomoctoWeb.HomeLive`).
  """
  import Ecto.Query

  alias Octomocto.Accounts.User
  alias Octomocto.Friends.Follow
  alias Octomocto.Notifications
  alias Octomocto.Repo

  @doc "The friends of the user: the users who follow the user back."
  def friends(user_id) do
    Repo.all(
      from u in User,
        join: out in Follow,
        on: out.followed_id == u.id and out.follower_id == ^user_id,
        join: back in Follow,
        on: back.follower_id == u.id and back.followed_id == ^user_id
    )
  end

  @doc "The users who follow the user. Friends are included."
  def followers(user_id) do
    Repo.all(
      from u in User, join: f in Follow, on: f.follower_id == u.id and f.followed_id == ^user_id
    )
  end

  @doc "The users that the user follows. Friends are included."
  def following(user_id) do
    Repo.all(
      from u in User, join: f in Follow, on: f.followed_id == u.id and f.follower_id == ^user_id
    )
  end

  @doc "The number of followers and of followed users of the user."
  def counts(user_id) do
    Repo.one(
      from f in Follow,
        where: f.follower_id == ^user_id or f.followed_id == ^user_id,
        select: %{
          followers: count(f.follower_id) |> filter(f.followed_id == ^user_id),
          following: count(f.followed_id) |> filter(f.follower_id == ^user_id)
        }
    )
  end

  @doc "The ids of the users who follow the user. Friends are included."
  def follower_ids(user_id) do
    Repo.all(from f in Follow, where: f.followed_id == ^user_id, select: f.follower_id)
  end

  @doc "True when the user `follower_id` follows the user `followed_id`."
  def following?(follower_id, followed_id) do
    Repo.exists?(
      from f in Follow, where: f.follower_id == ^follower_id and f.followed_id == ^followed_id
    )
  end

  @doc "The ids of the users that the user follows. Friends are included."
  def followed_ids(user_id) do
    Repo.all(from f in Follow, where: f.follower_id == ^user_id, select: f.followed_id)
  end

  @doc """
  The user `follower_id` follows the user `followed_id`, and the user
  `followed_id` gets a notification. A follow that exists stays the same.
  A user cannot follow themself.
  """
  def follow(same_id, same_id), do: :ok

  def follow(follower_id, followed_id) do
    {count, _} =
      Repo.insert_all(
        Follow,
        [
          %{
            follower_id: follower_id,
            followed_id: followed_id,
            inserted_at: DateTime.utc_now(:second)
          }
        ],
        on_conflict: :nothing
      )

    # Only a new follow notifies (see `Octomocto.Notifications`)
    if count > 0, do: Notifications.followed(follower_id, followed_id)
    :ok
  end

  @doc """
  The user `follower_id` stops following the user `followed_id`. When they
  were friends, they are not friends after this: the follow back stays.
  """
  def unfollow(follower_id, followed_id) do
    Repo.delete_all(
      from f in Follow, where: f.follower_id == ^follower_id and f.followed_id == ^followed_id
    )

    Notifications.unfollowed(follower_id, followed_id)
    :ok
  end

  @doc """
  Makes friends of the creator of the game and of each player who joined
  from a shared link, from the `state` of a finished game. Does nothing for
  a game with no creator, or when the creator is a guest or not in the game.
  A follow that exists stays the same.
  """
  def maybe_record(state) do
    with creator when is_binary(creator) <- Map.get(state, :creator),
         %{user_id: user_id} when user_id != nil <- state.players[creator] do
      friend_ids =
        for {id, player} <- state.players,
            id != creator,
            player.user_id not in [nil, user_id],
            # A seat from before the lobby source has no `:from_lobby`
            not Map.get(player, :from_lobby, false),
            uniq: true,
            do: player.user_id

      record(user_id, friend_ids)
    end

    :ok
  end

  defp record(_user_id, []), do: nil

  defp record(user_id, friend_ids) do
    now = DateTime.utc_now(:second)

    rows =
      Enum.flat_map(friend_ids, fn friend_id ->
        [
          %{follower_id: user_id, followed_id: friend_id, inserted_at: now},
          %{follower_id: friend_id, followed_id: user_id, inserted_at: now}
        ]
      end)

    Repo.insert_all(Follow, rows, on_conflict: :nothing)
  end
end
