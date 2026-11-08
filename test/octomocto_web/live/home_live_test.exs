defmodule OctomoctoWeb.HomeLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.AccountsFixtures

  alias Octomocto.Friends.Follow
  alias Octomocto.{NimbleMosaic, OnlineUsers, Repo, Snap}

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

    test "recent asks a guest to sign in", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      view |> element("#game-tag-recent") |> render_click()

      assert_patch(view, ~p"/?tag=recent")
      assert has_element?(view, "#recent-sign-in")
      refute has_element?(view, "#games li")
    end

    test "an unknown tag shows all games", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tag=unknown")

      assert has_element?(view, "#game-tag-all[aria-pressed=true]")
      assert has_element?(view, "#game-schulte")
    end
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "sees the played games in the recent list, the last played first",
         %{conn: conn, user: user} do
      snap = %{user_id: user.id, score: 5, correct: 5, wrong: 0}
      mosaic_settings = %{"type" => "random", "mode" => "easy", "players" => 1}
      Snap.save_results("a", %{}, 0, [snap])
      NimbleMosaic.save_results("b", mosaic_settings, 1000, [%{user_id: user.id, score: 90}])
      Snap.save_results("c", %{}, 0, [snap])

      {:ok, view, _html} = live(conn, ~p"/?tag=recent")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#games > li > a")
        |> LazyHTML.attribute("id")

      assert ids == ["game-snap", "game-nimble-mosaic"]
    end

    test "gets the tag they clicked last when they open the front page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#game-tag-memory") |> render_click()

      assert {:error, {:live_redirect, %{to: "/?tag=memory"}}} = live(conn, ~p"/")
    end

    test "gets all games after they click all games", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      view |> element("#game-tag-memory") |> render_click()
      view |> element("#game-tag-all") |> render_click()

      assert {:ok, _view, _html} = live(conn, ~p"/")
    end

    test "does not save a tag that they only opened from a link", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/?tag=memory")

      assert {:ok, _view, _html} = live(conn, ~p"/")
    end

    test "sees a text in the recent list when they played no games", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/?tag=recent")

      assert has_element?(view, "#recent-empty")
    end

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
      assert has_element?(view, ~s(#game-set[href="/pt/set"]))
      assert has_element?(view, ~s(#game-sudoku[href="/sudoku"]))
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
