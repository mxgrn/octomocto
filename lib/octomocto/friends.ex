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

  Nothing makes a follow with no follow back yet, and nothing shows the
  friends yet.
  """
  alias Octomocto.Friends.Follow
  alias Octomocto.Repo

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
