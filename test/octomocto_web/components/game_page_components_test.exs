defmodule OctomoctoWeb.GamePageComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias OctomoctoWeb.GamePageComponents

  describe "lobby_games/1" do
    test "shows a started game that has no :finished key" do
      game = %{
        id: "abc",
        status: :started,
        players: [%{name: "Ann", away: false, turn: true}]
      }

      html =
        render_component(&GamePageComponents.lobby_games/1,
          games: [game],
          path: fn game -> "/memory/#{game.id}" end,
          icon: [],
          summary: []
        )

      assert html =~ ~s(id="lobby-game-abc")
    end
  end
end
