defmodule OctomoctoWeb.AfterglowLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Afterglow.Turns

  test "alone, the page shows the first round and no grid setting", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/afterglow")

    assert has_element?(view, "#afterglow-first-round")
    refute has_element?(view, "#setting-size")
  end

  test "with 3 players, the smallest grid is 5 × 5", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/afterglow?players=3&size=4")

    assert has_element?(view, "#size-5[aria-current]")
    refute has_element?(view, "#size-4")
  end

  test "new game with players starts a game with turns and opens its page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/afterglow?players=2&size=6")

    {:error, {:redirect, %{to: "/afterglow/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{players_needed: 2, size: 6}} = Turns.join(id)
    assert html_response(get(conn, ~p"/afterglow/#{id}"), 200) =~ "afterglow-turns-main"
  end
end
