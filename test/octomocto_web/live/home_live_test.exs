defmodule OctomoctoWeb.HomeLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Friends.Follow
  alias Octomocto.{OnlineUsers, Repo}

  defp make_friends(user, friend) do
    Repo.insert_all(Follow, [
      %{follower_id: user.id, followed_id: friend.id, inserted_at: DateTime.utc_now(:second)},
      %{follower_id: friend.id, followed_id: user.id, inserted_at: DateTime.utc_now(:second)}
    ])
  end

  test "a guest sees a link to sign in in place of the friends", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#friends-online-sign-in")
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "sees that no friend is online", %{conn: conn, user: user} do
      make_friends(user, user_fixture())

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#friends-online-empty")
    end

    test "sees a friend who comes online, with the activity", %{conn: conn, user: user} do
      friend = user_fixture()
      make_friends(user, friend)
      {:ok, view, _html} = live(conn, ~p"/")
      OnlineUsers.subscribe()

      OnlineUsers.track(self(), friend.id, %{kind: "memory", doing: "playing"})

      # The page gets the same message
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 2000
      assert view |> element("#friend-online-#{friend.id}") |> render() =~ "Playing Memory"
    end

    test "does not see a user who only follows the user", %{conn: conn, user: user} do
      follower = user_fixture()

      Repo.insert_all(Follow, [
        %{follower_id: follower.id, followed_id: user.id, inserted_at: DateTime.utc_now(:second)}
      ])

      OnlineUsers.track(self(), follower.id, %{kind: nil, doing: nil})
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#friend-online-#{follower.id}")
    end
  end
end
