defmodule Octomocto.Players do
  @moduledoc """
  The public profiles of users and guests, by their public id (see
  `Octomocto.PublicId`). A profile shows the name, the date of the first
  visit that the site saved, the games played, the time of the last
  finished game and, for a user, the number of friends and whether the
  user is online now (guests are never online, see
  `Octomocto.OnlineUsers`). A guest has a profile only after it has a row (see
  `Octomocto.Guests.Guest`).
  """
  import Ecto.Query

  alias Octomocto.Accounts
  alias Octomocto.Accounts.User
  alias Octomocto.Guests.Guest
  alias Octomocto.{Friends, OnlineUsers, Repo, Stats}

  @doc """
  The profile of the user or the guest with the `public_id`, or nil. The
  `:friends` count is nil for a guest: guests have no friends.
  `:last_played_at` is nil for a player with no finished games.
  """
  def profile(public_id) when is_binary(public_id) do
    cond do
      user = Repo.one(from u in User, where: u.public_id == ^public_id) ->
        %{
          name: Accounts.public_name(user) || "Guest",
          guest: false,
          avatar_url: user.avatar_url,
          joined_at: user.inserted_at,
          games: Stats.games_of(:user_id, user.id),
          last_played_at: Stats.last_played_of(:user_id, user.id),
          online: Map.has_key?(OnlineUsers.activities([user.id]), user.id),
          friends: length(Friends.friends(user.id))
        }

      guest = Repo.one(from g in Guest, where: g.public_id == ^public_id) ->
        %{
          name: guest.name,
          guest: true,
          avatar_url: nil,
          joined_at: guest.inserted_at,
          games: Stats.games_of(:guest_id, guest.id),
          last_played_at: Stats.last_played_of(:guest_id, guest.id),
          online: false,
          friends: nil
        }

      true ->
        nil
    end
  end

  @doc "The user with the `public_id`, or nil. A guest has no user."
  def user(public_id) when is_binary(public_id),
    do: Repo.one(from u in User, where: u.public_id == ^public_id)

  @doc """
  The public id of the user `user_id` or of the guest `guest_id`, or nil
  when there is none: a guest without a row has no profile yet.
  """
  def public_id(user_id, guest_id)
  def public_id(nil, nil), do: nil

  def public_id(nil, guest_id),
    do: Repo.one(from g in Guest, where: g.id == ^guest_id, select: g.public_id)

  def public_id(user_id, _guest_id),
    do: Repo.one(from u in User, where: u.id == ^user_id, select: u.public_id)
end
