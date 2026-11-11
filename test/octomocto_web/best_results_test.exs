defmodule OctomoctoWeb.BestResultsTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias OctomoctoWeb.BestResults

  # The settings of the results, as the database gives them back
  @settings [
    {"snap", %{"back" => 3, "players" => 1}},
    {"echo", %{"pads" => 6, "players" => 2}},
    {"afterglow", %{"players" => 1}},
    {"afterglow", %{"players" => 3, "size" => 7}},
    {"mahjong", %{"layout" => "turtle", "players" => 2}},
    {"overlap", %{"symbols" => 8, "players" => 3}},
    {"graze", %{"players" => 2}},
    {"nimble-mosaic", %{"type" => "random", "mode" => "normal", "players" => 2}},
    {"schulte", %{"size" => 7, "marks" => true, "players" => 2}},
    {"set", %{"mode" => "easy", "players" => 2}},
    {"memory", %{"set" => 3, "cards" => 24, "players" => 1, "bombs" => 3}},
    {"memory", %{"set" => 2, "cards" => 20, "players" => 2}},
    {"sudoku", %{"difficulty" => "hard", "players" => 2}},
    {"trains", %{"switch_count" => 8, "trains_per_house" => 3, "pace" => "hard", "players" => 2}}
  ]

  for {game, settings} <- @settings do
    test "the link of #{game} #{inspect(settings)} opens the same Best results", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, BestResults.path(unquote(game), unquote(Macro.escape(settings))))

      {_context, page_settings} = :sys.get_state(view.pid).socket.assigns.best_query
      assert stringify(page_settings) == unquote(Macro.escape(settings))
    end
  end

  defp stringify(settings), do: settings |> Jason.encode!() |> Jason.decode!()
end
