defmodule OctomoctoWeb.TrainsLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Trains
  alias Octomocto.Trains.Store

  test "the settings page has the Campaign tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/trains")

    assert view |> element("#tab-campaign") |> render_click()
    assert_patch(view, ~p"/trains/campaign")
  end

  test "a player of a match changes the settings of the next round", %{conn: conn} do
    id =
      Trains.create_game(%{
        players: 2,
        switch_count: 4,
        trains_per_house: 1,
        pace: "easy",
        public: true
      })

    {:ok, player_id, _} = Trains.join(id)
    {:ok, _, %{seed: seed}} = Trains.join(id)
    Trains.finish(id, player_id, seed, 1)
    token = Phoenix.Token.sign(OctomoctoWeb.Endpoint, "trains player", {id, player_id})

    {:ok, view, _html} =
      conn |> put_connect_params(%{"match_token" => token}) |> live(~p"/trains?match=#{id}")

    assert has_element?(view, "#match-score")
    refute has_element?(view, "#setting-players")
    refute has_element?(view, "#setting-visibility")

    view |> element("#pace-hard") |> render_click()
    {:error, {:redirect, %{to: to}}} = view |> element("#new-game") |> render_click()

    assert to == ~p"/trains/#{id}"
    assert %{pace: "hard", needed: 2, public: true, editing: nil} = Store.read(id)
  end

  for locale <- ~w(pt de ru fr uk pl it es ja vi tr ar) do
    test "/#{locale}/trains shows Right on Track in the language", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/#{unquote(locale)}/trains")

      assert has_element?(view, "#new-game")
      # The logo goes to the front page in the same language
      assert has_element?(view, ~s|a[href="/#{unquote(locale)}"]|)
    end
  end

  test "a new game on a localized page opens in the same language", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/pt/trains")

    assert {:error, {:redirect, %{to: "/pt/trains/" <> _id}}} =
             view |> element("#new-game") |> render_click()
  end
end
