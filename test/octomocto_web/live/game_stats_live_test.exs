defmodule OctomoctoWeb.GameStatsLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Guests.Guest
  alias Octomocto.{Repo, Schulte}

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "shows the players with the most games first, with links to the profiles", %{conn: conn} do
    user = user_fixture()
    guest_id = Ecto.UUID.generate()
    guest = %{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}

    Schulte.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Schulte.save_results("b", @settings, 1000, [guest])
    Schulte.save_results("c", @settings, 1000, [guest])

    {:ok, view, _html} = live(conn, ~p"/stats/schulte")

    guest_public_id = Repo.get!(Guest, guest_id).public_id
    assert has_element?(view, ~s|#top-player-1 a[href="/players/#{guest_public_id}"]|)
    assert view |> element("#top-player-1") |> render() =~ "2"
    assert has_element?(view, ~s|#top-player-2 a[href="/players/#{user.public_id}"]|)
  end

  test "shows an empty list for a game without results", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats/memory")

    assert has_element?(view, "#top-players-empty")
  end

  test "gives 404 for an unknown game", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/stats/unknown") end
  end

  test "the stats page links each game to its stats page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/stats")

    assert has_element?(view, ~s|#stats-memory a[href="/stats/memory"]|)
  end
end
