defmodule Octomocto.NotificationsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.{Friends, Notifications}

  setup do
    %{follower: user_fixture().id, user: user_fixture().id}
  end

  test "a follow notifies the followed user", %{follower: follower, user: user} do
    Notifications.subscribe(user)

    Friends.follow(follower, user)

    assert_receive {:unread_notifications, 1}
    assert [%{kind: :followed, actor_id: ^follower}] = Notifications.list(user)
  end

  test "mark_seen/1 makes all notifications read", %{follower: follower, user: user} do
    Friends.follow(follower, user)

    Notifications.mark_seen(user)

    assert Notifications.unread_count(user) == 0
  end

  test "an unfollow removes an unread notification", %{follower: follower, user: user} do
    Friends.follow(follower, user)

    Friends.unfollow(follower, user)

    assert Notifications.unread_count(user) == 0
    Friends.follow(follower, user)
    assert Notifications.unread_count(user) == 1
  end

  test "a second follow after a read one does not notify again",
       %{follower: follower, user: user} do
    Friends.follow(follower, user)
    Notifications.mark_seen(user)
    Friends.unfollow(follower, user)

    assert Notifications.list(user) == []
    Friends.follow(follower, user)

    assert Notifications.unread_count(user) == 0
    assert [_read] = Notifications.list(user)
  end

  test "the friends from a shared game link get no notifications",
       %{follower: creator, user: user} do
    Friends.maybe_record(%{
      creator: "a",
      players: %{"a" => %{user_id: creator}, "b" => %{user_id: user}}
    })

    assert Notifications.unread_count(user) == 0
    assert Notifications.unread_count(creator) == 0
  end
end
