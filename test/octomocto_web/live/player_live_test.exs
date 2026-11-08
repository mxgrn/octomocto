defmodule OctomoctoWeb.PlayerLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Guests.Guest
  alias Octomocto.{OnlineUsers, Repo, NimbleMosaic}
  alias OctomoctoWeb.PlayerLive

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows the games of a user in each game and the follows", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert view |> element("#player-games") |> render() =~ "1"
    assert has_element?(view, "#player-game-nimble-mosaic")
    assert has_element?(view, "#player-follows")
  end

  test "shows a graph of the last 30 days for each game", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert has_element?(
             view,
             ~s|#player-activity-nimble-mosaic[aria-label="1 game in the last 30 days"]|
           )
  end

  test "hides the games not played in the last 30 days", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    Repo.update_all(NimbleMosaic.Result,
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -31, :day)]
    )

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    refute has_element?(view, "#player-game-nimble-mosaic")
    assert has_element?(view, "#player-no-recent-games")
  end

  test "shows the photo of a user", %{conn: conn} do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(avatar_url: "https://example.com/max.jpg")
    |> Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert has_element?(view, ~s|#player-avatar[src="https://example.com/max.jpg"]|)
    refute has_element?(view, "#player-initial")
  end

  test "shows no follows for a guest", %{conn: conn} do
    guest_id = Ecto.UUID.generate()

    NimbleMosaic.save_results("a", @settings, 1000, [
      %{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}
    ])

    {:ok, view, _html} = live(conn, ~p"/players/#{Repo.get!(Guest, guest_id).public_id}")

    assert has_element?(view, "#player-guest")
    refute has_element?(view, "#player-follows")
  end

  test "shows how long ago a player last played", %{conn: conn} do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert view |> element("#player-last-active") |> render() =~ "just now"
    refute has_element?(view, "#player-online")
  end

  test "shows how long ago a player joined", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/players/#{user_fixture().public_id}")

    assert view |> element("#player-joined") |> render() =~ "just now"
  end

  test "shows an online user as online now", %{conn: conn} do
    user = user_fixture()
    OnlineUsers.track(self(), user.id, %{kind: nil, doing: nil})

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert has_element?(view, "#player-online")
  end

  test "shows no last active time for a user with no games", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/players/#{user_fixture().public_id}")

    refute has_element?(view, "#player-last-active")
  end

  test "ago/2 gives the time in the largest whole unit" do
    now = ~U[2026-11-04 12:00:00Z]

    assert PlayerLive.ago(~U[2026-11-04 11:59:30Z], now) == "just now"
    assert PlayerLive.ago(~U[2026-11-04 11:59:00Z], now) == "1 minute ago"
    assert PlayerLive.ago(~U[2026-11-04 09:00:00Z], now) == "3 hours ago"
    assert PlayerLive.ago(~U[2026-11-02 12:00:00Z], now) == "2 days ago"
    assert PlayerLive.ago(~U[2026-07-04 12:00:00Z], now) == "4 months ago"
    assert PlayerLive.ago(~U[2024-11-04 12:00:00Z], now) == "2 years ago"
  end

  test "opens the profile of a user at the handle", %{conn: conn} do
    {:ok, user} = Octomocto.Accounts.update_user_profile(user_fixture(), %{handle: "ada"})

    {:ok, view, _html} = live(conn, ~p"/players/ada")

    assert has_element?(view, ~s|#player-followers-link[href="/players/ada/followers"]|)

    assert {:error, {:live_redirect, %{to: "/players/ada"}}} =
             live(conn, ~p"/players/#{user.public_id}")
  end

  test "the results link to the handle of the user", %{conn: conn} do
    {:ok, user} = Octomocto.Accounts.update_user_profile(user_fixture(), %{handle: "ada"})
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic?board=random")

    assert has_element?(view, ~s|#best-results a[href="/players/ada"]|)
  end

  test "gives 404 for an unknown public id", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/players/unknown1") end
  end

  test "the best results link to the profile of the user", %{conn: conn} do
    user = user_fixture()

    NimbleMosaic.save_results(
      "a",
      %{"type" => "random", "mode" => "easy", "players" => 2},
      1000,
      [
        %{user_id: user.id, score: 90}
      ]
    )

    {:ok, view, _html} = live(conn, ~p"/nimble-mosaic?board=random&players=2")

    assert has_element?(view, ~s|#best-results a[href="/players/#{user.public_id}"]|)
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "has a link to the own profile in the menu", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|#profile-link[href="/players/#{user.public_id}"]|)
    end

    test "has a link to the own handle in the menu", %{conn: conn, user: user} do
      {:ok, _user} = Octomocto.Accounts.update_user_profile(user, %{handle: "ada"})

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|#profile-link[href="/players/ada"]|)
    end
  end

  describe "follow" do
    setup :register_and_log_in_user

    test "follows and unfollows a user", %{conn: conn, user: user} do
      player = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/players/#{player.public_id}")

      view |> element("#follow-button") |> render_click()
      assert Octomocto.Friends.following?(user.id, player.id)

      view |> element("#unfollow-button") |> render_click()
      refute Octomocto.Friends.following?(user.id, player.id)
      assert has_element?(view, "#follow-button")
    end

    test "asks before an unfollow ends a friendship", %{conn: conn, user: user} do
      player = user_fixture()
      Octomocto.Friends.follow(player.id, user.id)
      {:ok, view, _html} = live(conn, ~p"/players/#{player.public_id}")

      assert view |> element("#follow-button") |> render() =~ "Follow back"
      view |> element("#follow-button") |> render_click()

      assert view |> element("#player-following-link") |> render() =~ "1"
      assert view |> element("#unfollow-button[data-confirm]") |> render() =~ "Friends"
    end

    test "has no button on the own profile", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

      refute has_element?(view, "#follow-button")
    end
  end

  test "has no follow button for a guest", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/players/#{user_fixture().public_id}")

    refute has_element?(view, "#follow-button")
  end
end
