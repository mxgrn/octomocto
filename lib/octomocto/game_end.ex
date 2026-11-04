defmodule Octomocto.GameEnd do
  @moduledoc """
  What happens after a game saves the results of a finished field. Each
  game process calls `finished/1` with its full state, right after it
  saves the results.
  """
  alias Octomocto.Friends

  @doc "Runs the effects of the end of a field of the game."
  def finished(state) do
    Friends.maybe_record(state)
  end
end
