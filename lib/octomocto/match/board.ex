defmodule Octomocto.Match.Board do
  @moduledoc """
  The sizes and the shapes of a Match field. A field has a number of cards
  that is a multiple of the cards in a set (2 for pairs, 3 for triplets),
  and that fits in a grid that is almost square. A grid can have one empty
  place (a gap) in the middle, when the number of cards is even.
  """

  alias Octomocto.Match.Themes

  # Dev config sets a small value for easier testing.
  @min_cards Application.compile_env(:octomocto, :match_min_cards, 15)
  @max_cards 100

  @doc "The number of cards in a new field, before the player changes it."
  def default_cards(2), do: 16
  def default_cards(3), do: 15

  @doc """
  Gives the possible numbers of cards for the theme and the set size, the
  smallest first. A theme has a limit, because each card image can be in
  only one set.
  """
  def sizes(theme_name, set_size) do
    max_cards = min(Themes.get(theme_name).cards * set_size, @max_cards)

    @min_cards..max_cards//1
    |> Enum.filter(&(rem(&1, set_size) == 0 and layouts(&1) != []))
  end

  @doc """
  Gives the grids for the number of cards as `{columns, rows, gaps}`. The
  client picks the grid that fits its screen best.
  """
  def layouts(cards) do
    for columns <- 2..max(2, round(cards / 2))//1,
        rows = ceil(cards / columns),
        gaps = rows * columns - cards,
        gaps == 0 or (gaps == 1 and rem(cards, 2) == 0),
        columns * 2 >= rows and rows * 2 >= columns,
        do: {columns, rows, gaps}
  end

  @doc "Gives the possible size that is the nearest to the number of cards."
  def nearest_size(theme_name, set_size, cards) do
    Enum.min_by(sizes(theme_name, set_size), &abs(&1 - cards))
  end
end
