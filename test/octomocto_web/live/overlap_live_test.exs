defmodule OctomoctoWeb.OverlapLiveTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Octomocto.Overlap

  test "selects the Mix 1 theme by default", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/overlap")

    assert has_element?(view, "#theme-mix1[aria-current]")
    assert has_element?(view, "#theme-random[aria-checked=false]")
  end

  test "the Random switch hides the themes and goes back to the last chosen theme",
       %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/overlap?theme=mix2")

    view |> element("#theme-random") |> render_click()

    assert_patch(view, ~p"/overlap?#{[theme: "random", players: 1]}")
    refute has_element?(view, "#overlap-themes")

    view |> element("#theme-random") |> render_click()

    assert_patch(view, ~p"/overlap?#{[theme: "mix2", players: 1]}")
    assert has_element?(view, "#theme-mix2[aria-current]")
  end

  test "new game starts a game with the theme", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/overlap?theme=mix2")

    {:error, {:redirect, %{to: "/overlap/" <> id}}} =
      view |> element("#new-game") |> render_click()

    assert {:ok, _player_id, %{theme: "mix2"}} = Overlap.join(id)
  end
end
