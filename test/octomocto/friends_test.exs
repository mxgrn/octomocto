defmodule Octomocto.FriendsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.Friends
  alias Octomocto.Friends.Follow

  defp pairs do
    Repo.all(from f in Follow, select: {f.follower_id, f.followed_id}) |> Enum.sort()
  end

  test "maybe_record/1 makes friends of the creator and each player from a shared link" do
    [creator, shared, other, lobby] = for _ <- 1..4, do: user_fixture().id

    state = %{
      creator: "a",
      players: %{
        "a" => %{user_id: creator, from_lobby: false},
        "b" => %{user_id: shared, from_lobby: false},
        "c" => %{user_id: other, from_lobby: false},
        "d" => %{user_id: lobby, from_lobby: true},
        "e" => %{user_id: nil, from_lobby: false}
      }
    }

    Friends.maybe_record(state)

    assert pairs() ==
             Enum.sort([{creator, shared}, {shared, creator}, {creator, other}, {other, creator}])
  end

  test "maybe_record/1 keeps a pair that is already friends the same" do
    [creator, friend] = for _ <- 1..2, do: user_fixture().id

    state = %{
      creator: "a",
      players: %{"a" => %{user_id: creator}, "b" => %{user_id: friend, from_lobby: false}}
    }

    Friends.maybe_record(state)
    Friends.maybe_record(state)

    assert length(pairs()) == 2
  end

  test "maybe_record/1 does nothing for a game with no creator, or with a guest creator" do
    user = user_fixture().id
    players = %{"a" => %{user_id: nil}, "b" => %{user_id: user, from_lobby: false}}

    Friends.maybe_record(%{creator: false, players: players})
    Friends.maybe_record(%{creator: "a", players: players})

    assert pairs() == []
  end

  test "follow/2 makes friends when the other user follows back" do
    [a, b] = for _ <- 1..2, do: user_fixture().id

    Friends.follow(a, b)
    assert Friends.following?(a, b)
    assert Friends.friends(a) == []

    Friends.follow(b, a)
    assert [%{id: ^b}] = Friends.friends(a)
  end

  test "unfollow/2 ends a friendship and keeps the follow back" do
    [a, b] = for _ <- 1..2, do: user_fixture().id
    Friends.follow(a, b)
    Friends.follow(b, a)

    Friends.unfollow(a, b)

    assert pairs() == [{b, a}]
    assert Friends.friends(b) == []
  end
end
