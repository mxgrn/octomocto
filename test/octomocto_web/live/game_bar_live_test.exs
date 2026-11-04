defmodule OctomoctoWeb.GameBarLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Octomocto.GameHelpers

  alias Octomocto.Memory
  alias Octomocto.Memory.Board
  alias OctomoctoWeb.GameBarLive

  defp bar(conn, kind, id) do
    {:ok, view, _html} =
      live_isolated(conn, GameBarLive, session: %{"kind" => kind, "id" => id, "locale" => "en"})

    view
  end

  # The visible text of the bar, with single spaces
  defp summary(view) do
    view
    |> element("#game-bar-summary")
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.text()
    |> String.split()
    |> Enum.join(" ")
  end

  test "shows the settings, the number of players and the visibility", %{conn: conn} do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(nimble_mosaic_game(id, players: 2))

    view = bar(conn, "nimble-mosaic", id)

    assert summary(view) == "Random board · Easy · 2 players · Private link"
  end

  test "shows the new settings when a player changes them between two fields", %{conn: conn} do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(memory_game(id, players: 2))
    Ecto.Adapters.SQL.Sandbox.allow(Octomocto.Repo, self(), pid)
    {:ok, first, _} = Memory.join(id)
    {:ok, _, _} = Memory.join(id)
    view = bar(conn, "memory", id)

    # The first player turns all pairs, so the turn does not change
    %{cards: cards} = :sys.get_state(pid)

    for {_image, pair} <- cards |> Enum.with_index() |> Enum.group_by(&elem(&1, 0).image),
        {_card, i} <- pair,
        do: Memory.flip(id, first, i)

    [_, cards | _] = Board.sizes("monsters", 2)
    {:ok, _} = Memory.edit_settings(id, first)
    :ok = Memory.change_settings(id, first, %{theme: "monsters", set: 2, cards: cards})

    assert summary(view) =~ "#{cards} cards"
  end
end
