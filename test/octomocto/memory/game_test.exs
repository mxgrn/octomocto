defmodule Octomocto.Memory.GameTest do
  use ExUnit.Case, async: true

  alias Octomocto.Memory.Game

  test "lobby_entry/1 gives no bombs for a stored state from before the bombs" do
    player = %{name: "Zippy Sponge", color_name: "lime", left: nil, joined_at: 1, score: 0}

    state = %{
      id: "game",
      public: true,
      listed: true,
      needed: 2,
      created_at: 1,
      campaign: nil,
      theme: "monsters",
      set: 2,
      size: 60,
      turn: "player",
      players: %{"player" => player}
    }

    assert %{settings: %{bombs: 0}} = Game.lobby_entry(state)
  end
end
