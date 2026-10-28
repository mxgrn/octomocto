defmodule Octomocto.GameHelpers do
  @moduledoc """
  Child specs of games for `start_supervised!/1` in tests. Each game is
  private and for one player. The games start without the countdown, and
  remove a player at once when its process stops, unless the config says
  otherwise.
  """

  @defaults %{players: 1, public: false, countdown_ms: 0, rejoin_grace_ms: 0}

  @doc "A Schulte game with a random layout in the easy mode."
  def schulte_game(id, config \\ []),
    do: game(Octomocto.Schulte.Game, id, %{layout: :random, mode: :easy}, config)

  @doc "A sudoku game with an easy puzzle."
  def sudoku_game(id, config \\ []),
    do: game(Octomocto.Sudoku.Game, id, %{difficulty: "easy"}, config)

  @doc "A Set game in the easy mode (27 cards)."
  def set_game(id, config \\ []), do: game(Octomocto.SetGame.Game, id, %{mode: "easy"}, config)

  def mahjong_game(id, config \\ []), do: game(Octomocto.Mahjong.Game, id, %{}, config)

  def overlap_game(id, config \\ []), do: game(Octomocto.Overlap.Game, id, %{}, config)

  @doc "An Echo game with 4 pads."
  def echo_game(id, config \\ []), do: game(Octomocto.Echo.Game, id, %{pads: 4}, config)

  defp game(module, id, settings, config) do
    {module, {id, @defaults |> Map.merge(settings) |> Map.merge(Map.new(config))}}
  end
end
