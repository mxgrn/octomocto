defmodule OctomoctoWeb.LobbyTabTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  # The games without a campaign: the New game and Lobby tabs
  @paths ~w(/afterglow /echo /graze /mahjong /nimble-mosaic /overlap /schulte /set /sudoku /pt/echo)

  for path <- @paths do
    test "#{path} shows the settings on the New game tab only", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      assert has_element?(view, "#tab-free[aria-current]")
      assert has_element?(view, "#new-game")
      refute has_element?(view, "#lobby-games")
    end

    test "#{path} shows the ongoing games on the Lobby tab only", %{conn: conn} do
      {:ok, view, _html} = live(conn, unquote(path))

      view |> element("#tab-lobby") |> render_click()

      assert_patch(view, unquote(path) <> "/lobby")
      assert has_element?(view, "#tab-lobby[aria-current]")
      assert has_element?(view, "#lobby-games")
      refute has_element?(view, "#new-game")
    end
  end
end
