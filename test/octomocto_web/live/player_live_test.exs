defmodule OctomoctoWeb.PlayerLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Guests.Guest
  alias Octomocto.{Repo, Schulte}

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows the games of a user in each game and the friends", %{conn: conn} do
    user = user_fixture()
    Schulte.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])

    {:ok, view, _html} = live(conn, ~p"/players/#{user.public_id}")

    assert view |> element("#player-games") |> render() =~ "1"
    assert has_element?(view, "#player-game-schulte")
    assert has_element?(view, "#player-friends")
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

  test "shows no friends for a guest", %{conn: conn} do
    guest_id = Ecto.UUID.generate()

    Schulte.save_results("a", @settings, 1000, [
      %{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}
    ])

    {:ok, view, _html} = live(conn, ~p"/players/#{Repo.get!(Guest, guest_id).public_id}")

    assert has_element?(view, "#player-guest")
    refute has_element?(view, "#player-friends")
  end

  test "gives 404 for an unknown public id", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/players/unknown1") end
  end

  test "the best results link to the profile of the user", %{conn: conn} do
    user = user_fixture()

    Schulte.save_results("a", %{"type" => "random", "mode" => "easy", "players" => 2}, 1000, [
      %{user_id: user.id, score: 90}
    ])

    {:ok, view, _html} = live(conn, ~p"/schulte?board=random&players=2")

    assert has_element?(view, ~s|#best-results a[href="/players/#{user.public_id}"]|)
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "has a link to the own profile in the menu", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, ~s|#profile-link[href="/players/#{user.public_id}"]|)
    end
  end
end
