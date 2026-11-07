defmodule Octomocto.Stats.CounterTest do
  # Not async: the counter is one for all tests
  use ExUnit.Case, async: false

  alias Octomocto.Stats

  test "adds one for each finished game" do
    count = Stats.Counter.get()

    Stats.broadcast_game_finished()
    _ = :sys.get_state(Stats.Counter)

    assert Stats.Counter.get() == count + 1
  end
end
