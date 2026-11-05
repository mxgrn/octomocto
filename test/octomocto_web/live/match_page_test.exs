defmodule OctomoctoWeb.MatchPageTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest
  import Octomocto.GameHelpers

  alias Octomocto.{Echo, Schulte}

  # The live view of the match page with the token of the player
  defp live_match(conn, path, salt, id, player_id) do
    token = Phoenix.Token.sign(OctomoctoWeb.Endpoint, salt, {id, player_id})
    conn |> put_connect_params(%{"match_token" => token}) |> live(path)
  end

  test "a player of a race changes the settings of the next game", %{conn: conn} do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(schulte_game(id, players: 2))
    {:ok, first, _} = Schulte.join(id)
    {:ok, _, _} = Schulte.join(id)
    for n <- 1..25, do: Schulte.pick(id, first, n)

    {:ok, view, _html} =
      live_match(conn, ~p"/schulte?match=#{id}", "schulte_table player", id, first)

    assert has_element?(view, "#match-player-#{first}", "1")
    refute has_element?(view, "#setting-players")
    refute has_element?(view, "#setting-visibility")

    view |> element("#size-7") |> render_click()
    {:error, {:redirect, %{to: to}}} = view |> element("#new-game") |> render_click()

    assert to == ~p"/schulte/#{id}"
    assert {:ok, nil, %{size: 7, players_needed: 2, editing: nil}} = Schulte.watch(id)
  end

  test "a player of a game with turns changes the settings of the next game", %{conn: conn} do
    id = Echo.create_game(%{pads: 4, players: 2, public: true})
    {:ok, first, _} = Echo.join(id)
    {:ok, second, _} = Echo.join(id)
    Echo.press(id, first, 2)
    Echo.press(id, second, 3)

    {:ok, view, _html} = live_match(conn, ~p"/echo?match=#{id}", "echo player", id, second)

    view |> element("#pads-6") |> render_click()
    {:error, {:redirect, %{to: to}}} = view |> element("#new-game") |> render_click()

    assert to == ~p"/echo/#{id}"
    assert {:ok, nil, %{pads: 6, finished: false}} = Echo.watch(id)
  end
end
