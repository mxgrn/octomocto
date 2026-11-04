defmodule OctomoctoWeb.PlayerFriendsLiveTest do
  use OctomoctoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Friends.Follow
  alias Octomocto.Guests.Guest
  alias Octomocto.{OnlineUsers, Repo, Schulte}

  defp make_friends(user, friend) do
    Repo.insert_all(Follow, [
      %{follower_id: user.id, followed_id: friend.id, inserted_at: DateTime.utc_now(:second)},
      %{follower_id: friend.id, followed_id: user.id, inserted_at: DateTime.utc_now(:second)}
    ])
  end

  test "the profile links to the friends of the user", %{conn: conn} do
    user = user_fixture()

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert has_element?(view, ~s|#player-friends-link[href="/players/#{user.public_id}/friends"]|)
  end

  test "a guest sees the friends without the online state", %{conn: conn} do
    user = user_fixture()
    friend = user_fixture()
    make_friends(user, friend)
    OnlineUsers.track(self(), friend.id, %{kind: "memory", doing: "playing"})

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/friends")

    assert has_element?(
             view,
             ~s|#player-friend-#{friend.id} a[href="/players/#{friend.public_id}"]|
           )

    refute has_element?(view, "#player-friend-status-#{friend.id}")
  end

  test "shows that a user has no friends", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/players/#{user_fixture().public_id}/friends")

    assert has_element?(view, "#player-friends-empty")
  end

  test "gives 404 for a guest", %{conn: conn} do
    guest_id = Ecto.UUID.generate()

    Schulte.save_results("a", %{"type" => "random", "mode" => "easy", "players" => 1}, 1000, [
      %{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}
    ])

    public_id = Repo.get!(Guest, guest_id).public_id
    assert_error_sent 404, fn -> get(conn, ~p"/players/#{public_id}/friends") end
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "sees the online state only of the own friends", %{conn: conn, user: viewer} do
      user = user_fixture()
      shared = user_fixture()
      other = user_fixture()
      make_friends(user, shared)
      make_friends(user, other)
      make_friends(viewer, shared)

      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/friends")

      assert has_element?(view, ~s|#player-friend-status-#{shared.id}[data-online="false"]|)
      refute has_element?(view, "#player-friend-status-#{other.id}")
    end

    test "sees an own friend who comes online, with the activity", %{conn: conn, user: viewer} do
      user = user_fixture()
      friend = user_fixture()
      make_friends(user, friend)
      make_friends(viewer, friend)
      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/friends")
      OnlineUsers.subscribe()

      OnlineUsers.track(self(), friend.id, %{kind: "memory", doing: "playing"})

      # The page gets the same message
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 2000
      assert has_element?(view, ~s|#player-friend-status-#{friend.id}[data-online="true"]|)
      assert view |> element("#player-friend-#{friend.id}") |> render() =~ "Playing Memory"
    end
  end
end
