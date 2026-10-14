defmodule Octomocto.GameStoreTest do
  use ExUnit.Case, async: true

  # A store module made with `use Octomocto.GameStore`
  alias Octomocto.Schulte.Store

  test "read/1 gives the state that write/1 wrote, and nil after delete/1" do
    id = "game-#{System.unique_integer([:positive])}"

    Store.write(%{id: id, next: 5})
    assert Store.read(id) == %{id: id, next: 5}

    Store.delete(id)
    assert Store.read(id) == nil
  end

  test "read/1 gives nil for an unknown game" do
    assert Store.read("unknown") == nil
  end
end
