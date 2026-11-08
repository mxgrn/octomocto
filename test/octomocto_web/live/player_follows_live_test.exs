defmodule OctomoctoWeb.PlayerFollowsLiveTest do
  use OctomoctoWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Guests.Guest
  alias Octomocto.{Friends, OnlineUsers, Repo, NimbleMosaic}

  defp make_friends(user, friend) do
    Friends.follow(user.id, friend.id)
    Friends.follow(friend.id, user.id)
  end

  test "the profile links to the followers and the followed users", %{conn: conn} do
    user = user_fixture()

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert has_element?(
             view,
             ~s|#player-followers-link[href="/players/#{user.public_id}/followers"]|
           )

    assert has_element?(
             view,
             ~s|#player-following-link[href="/players/#{user.public_id}/following"]|
           )
  end

  test "opens the lists at the handle of the user", %{conn: conn} do
    {:ok, user} = Octomocto.Accounts.update_user_profile(user_fixture(), %{handle: "ada"})

    {:ok, view, _html} = live(conn, ~p"/players/ada/followers")

    assert has_element?(view, ~s|a[href="/players/ada/following"]|)

    assert {:error, {:live_redirect, %{to: "/players/ada/following"}}} =
             live(conn, ~p"/players/#{user.public_id}/following")
  end

  test "shows the followers and the followed users", %{conn: conn} do
    user = user_fixture()
    follower = user_fixture()
    followed = user_fixture()
    Friends.follow(follower.id, user.id)
    Friends.follow(user.id, followed.id)

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/followers")

    assert has_element?(view, "#player-follow-#{follower.id}")
    refute has_element?(view, "#player-follow-#{followed.id}")

    view |> element("#player-follows-tab-following") |> render_click()

    assert_patch(view, ~p"/players/#{user.public_id}/following")
    assert has_element?(view, "#player-follow-#{followed.id}")
    refute has_element?(view, "#player-follow-#{follower.id}")
  end

  test "a guest sees no buttons and no online state", %{conn: conn} do
    user = user_fixture()
    friend = user_fixture()
    make_friends(user, friend)
    OnlineUsers.track(self(), friend.id, %{kind: "memory", doing: "playing"})

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/following")

    assert has_element?(
             view,
             ~s|#player-follow-#{friend.id} a[href="/players/#{friend.public_id}"]|
           )

    refute has_element?(view, "#player-follow-status-#{friend.id}")
    refute has_element?(view, "#player-follow-button-#{friend.id}")
  end

  test "shows that a user has no followers", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/players/#{user_fixture().public_id}/followers")

    assert has_element?(view, "#player-follows-empty")
  end

  test "gives 404 for a guest", %{conn: conn} do
    guest_id = Ecto.UUID.generate()

    NimbleMosaic.save_results(
      "a",
      %{"type" => "random", "mode" => "easy", "players" => 1},
      1000,
      [%{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}]
    )

    public_id = Repo.get!(Guest, guest_id).public_id
    assert_error_sent 404, fn -> get(conn, ~p"/players/#{public_id}/followers") end
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "follows back a follower who follows them", %{conn: conn, user: viewer} do
      follower = user_fixture()
      Friends.follow(follower.id, viewer.id)
      {:ok, view, _html} = live(conn, ~p"/players/#{viewer.public_id}/followers")

      assert has_element?(view, "#player-follow-follows-you-#{follower.id}")
      assert view |> element("#player-follow-button-#{follower.id}") |> render() =~ "Follow back"

      view |> element("#player-follow-button-#{follower.id}") |> render_click()

      assert Friends.following?(viewer.id, follower.id)
      assert view |> element("#player-follows-tab-following") |> render() =~ "1"
    end

    test "unfollows from the list, with a warning", %{conn: conn, user: viewer} do
      user = user_fixture()
      followed = user_fixture()
      Friends.follow(user.id, followed.id)
      Friends.follow(viewer.id, followed.id)
      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/following")

      view |> element("#player-unfollow-button-#{followed.id}[data-confirm]") |> render_click()

      refute Friends.following?(viewer.id, followed.id)
      assert has_element?(view, "#player-follow-button-#{followed.id}")
    end

    test "has no button on the own row", %{conn: conn, user: viewer} do
      user = user_fixture()
      Friends.follow(viewer.id, user.id)

      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/followers")

      assert has_element?(view, "#player-follow-#{viewer.id}")
      refute has_element?(view, "#player-follow-button-#{viewer.id}")
      refute has_element?(view, "#player-unfollow-button-#{viewer.id}")
    end

    test "cannot follow a player who is not in the list", %{conn: conn, user: viewer} do
      other = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/#{viewer.public_id}/followers")

      render_click(view, "follow", %{"id" => to_string(other.id)})

      refute Friends.following?(viewer.id, other.id)
    end

    test "sees the online state only of the own friends", %{conn: conn, user: viewer} do
      user = user_fixture()
      shared = user_fixture()
      other = user_fixture()
      make_friends(user, shared)
      make_friends(user, other)
      make_friends(viewer, shared)

      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/following")

      assert has_element?(view, ~s|#player-follow-status-#{shared.id}[data-online="false"]|)
      refute has_element?(view, "#player-follow-status-#{other.id}")
    end

    test "sees an own friend who comes online, with the activity", %{conn: conn, user: viewer} do
      user = user_fixture()
      friend = user_fixture()
      make_friends(user, friend)
      make_friends(viewer, friend)
      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}/followers")
      OnlineUsers.subscribe()

      OnlineUsers.track(self(), friend.id, %{kind: "memory", doing: "playing"})

      # The page gets the same message
      assert_receive %Phoenix.Socket.Broadcast{event: "presence_diff"}, 2000
      assert has_element?(view, ~s|#player-follow-status-#{friend.id}[data-online="true"]|)
      assert view |> element("#player-follow-#{friend.id}") |> render() =~ "Playing Memory"
    end
  end
end
