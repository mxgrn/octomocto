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

    test "the Join link of an open game says that the player comes from the lobby" do
      game = %{
        id: "abc",
        status: :open,
        players_needed: 2,
        seats_left: 1,
        players: [%{name: "Ann", away: false}]
      }

      html =
        render_component(&GamePageComponents.lobby_games/1,
          games: [game],
          path: fn game -> "/memory/#{game.id}" end,
          icon: [],
          summary: []
        )

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#join-abc")
             |> LazyHTML.attribute("href") ==
               ["/memory/abc?from=lobby"]
    end
  end

  describe "memory_games/1" do
    test "links to the other memory games" do
      html =
        render_component(&GamePageComponents.memory_games/1,
          id: "more-games",
          game: "afterglow",
          locale: "en"
        )

      assert html
             |> LazyHTML.from_fragment()
             |> LazyHTML.query("#more-games a")
             |> LazyHTML.attribute("href") == ["/memory", "/echo", "/snap", "/ink-trail"]
    end
  end
end
