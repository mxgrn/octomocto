defmodule Octomocto.GameEnd do
  @moduledoc """
  What happens after a game saves the results of a finished field. Each
  game process calls `finished/1` with its full state, right after it
  saves the results, and keeps the state that it gives.
  """
  alias Octomocto.{Friends, Seats}

  @doc """
  Runs the effects of the end of a field of the game. Gives the state with
  the public ids of the guests that got a row with this field (see
  `Octomocto.Seats.refresh_public_ids/1`).
  """
  def finished(state) do
    Friends.maybe_record(state)
    Seats.refresh_public_ids(state)
  end
end
