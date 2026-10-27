defmodule Octomocto.GameHelpers do
  @moduledoc """
  Child specs of games for `start_supervised!/1` in tests. The games start
  without the countdown, and remove a player at once when its process
  stops, unless the config says otherwise.
  """

  @fast %{countdown_ms: 0, rejoin_grace_ms: 0}

  @doc "A Schulte game: a random layout in the easy mode for one player, private by default."
  def schulte_game(id, config \\ []) do
    defaults = %{layout: :random, mode: :easy, players: 1, public: false}
    {Octomocto.Schulte.Game, {id, defaults |> Map.merge(@fast) |> Map.merge(Map.new(config))}}
  end
end
