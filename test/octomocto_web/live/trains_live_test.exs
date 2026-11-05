defmodule OctomoctoWeb.TrainsLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Trains
  alias Octomocto.Trains.Store

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
end
