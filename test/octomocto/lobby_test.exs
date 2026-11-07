defmodule Octomocto.LobbyTest do
  use ExUnit.Case, async: true

  alias Octomocto.Lobby

  test "games/1 sorts the started games by the time when they were made, finished or not" do
    entries = [
      %{id: "old", status: :ongoing, started_at: 3, created_at: 1, finished: false},
      %{id: "new", status: :ongoing, started_at: 2, created_at: 2, finished: true}
    ]

    assert Enum.map(Lobby.games(entries), & &1.id) == ["new", "old"]
  end
end
