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

  describe "the tag filter" do
    test "shows only the games with the tag", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-tag-memory") |> render_click()

      assert_patch(view, ~p"/?tag=memory")
      assert has_element?(view, "#game-memory")
      refute has_element?(view, "#game-schulte")
    end

    test "all clears the filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tag=memory")

      view |> element("#game-tag-all") |> render_click()

      assert_patch(view, ~p"/")
      assert has_element?(view, "#game-schulte")
    end

    test "an unknown tag shows all games", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tag=unknown")

      assert has_element?(view, "#game-tag-all[aria-current]")
      assert has_element?(view, "#game-schulte")
    end
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

  test "an open Overlap game shows the cover of its theme", %{conn: conn} do
    id = "game-#{System.unique_integer([:positive])}"

    start_supervised!(
      Octomocto.GameHelpers.overlap_game(id, theme: "mix2", players: 2, public: true)
    )

    {:ok, _player_id, _state} = Octomocto.Overlap.join(id)

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, ~s(#lobby-game-#{id} img[src^="/images/overlap/mix2/"]))
  end

  describe "in a language" do
    test "links a game with translations to its page in the language", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pt")

      assert has_element?(view, ~s(#game-memory[href="/pt/memory"]))
      assert has_element?(view, ~s(#game-set[href="/set"]))
    end

    test "keeps the language in the tag filter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/de")

      view |> element("#game-tag-memory") |> render_click()

      assert_patch(view, "/de?tag=memory")
    end

    test "the logo on a page in the language goes to the front page in the language",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/ru/memory")

      assert has_element?(view, ~s(#home-link[href="/ru"]))
    end

    test "the sign-in link goes to the sign-in page in the language", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/de")

      assert has_element?(view, ~s(#friends-online-sign-in[href="/de/signin"]))
    end
  end
end
