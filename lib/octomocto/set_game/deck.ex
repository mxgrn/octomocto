defmodule Octomocto.SetGame.Deck do
  @moduledoc """
  The cards of Set and the rules for sets. A card is an integer from 0 to
  80. Its 4 attributes are its digits in base 3: the number of shapes, the
  shape, the shading and the color.

  Three cards are a set when each attribute is the same on all 3 cards or
  different on all 3 cards. For digits from 0 to 2, that is when the sum
  of the digits can be divided by 3.

  The easy deck has the 27 cards that share one value of one attribute,
  for example all green cards. The attribute and its value are random.
  These rules are also correct for the easy deck.
  """

  @size 81
  # The number of cards on the table at the start, and after a set when
  # there is no extra card
  @table 12

  def modes, do: ~w(easy normal)

  def table, do: @table

  @doc "The cards of the mode in a random order."
  def shuffled("normal"), do: Enum.shuffle(0..(@size - 1))

  def shuffled("easy") do
    weight = Enum.random([1, 3, 9, 27])
    value = Enum.random(0..2)

    0..(@size - 1)
    |> Enum.filter(&(digit(&1, weight) == value))
    |> Enum.shuffle()
  end

  def set?([a, b, c]) when a != b and b != c and a != c do
    Enum.all?([1, 3, 9, 27], fn weight ->
      rem(digit(a, weight) + digit(b, weight) + digit(c, weight), 3) == 0
    end)
  end

  def set?(_cards), do: false

  @doc "True when some 3 of the cards are a set."
  def any_set?(cards) do
    # Two cards make exactly one third card that completes the set
    available = MapSet.new(cards)

    pairs(cards)
    |> Enum.any?(fn {a, b} -> MapSet.member?(available, third(a, b)) end)
  end

  # The card that makes a set with the two cards
  defp third(a, b) do
    Enum.reduce([1, 3, 9, 27], 0, fn weight, card ->
      card + rem(6 - digit(a, weight) - digit(b, weight), 3) * weight
    end)
  end

  defp digit(card, weight), do: rem(div(card, weight), 3)

  defp pairs([]), do: []
  defp pairs([card | rest]), do: Enum.map(rest, &{card, &1}) ++ pairs(rest)
end
