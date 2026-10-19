defmodule Octomocto.Overlap.Deck do
  @moduledoc """
  The cards of Overlap. There are 57 symbols and 57 cards with 8 symbols
  each. Any two cards have exactly one symbol in common.

  The cards are the lines of the projective plane of order 7. A symbol is
  a point of the plane: the points `{x, y}` with x and y from 0 to 6 are
  the symbols `7 * x + y` (0 to 48), the points at infinity of the 7 slopes
  are the symbols 49 to 55, and the point at infinity of the vertical lines
  is the symbol 56. Two lines of the plane always meet in exactly one
  point.

  The images of the symbols are in `priv/static/images/overlap/`, with the
  names `0.svg` to `56.svg`. They are Twemoji (CC-BY 4.0, Twitter, Inc. and
  other contributors, https://github.com/jdecked/twemoji).
  """

  @order 7

  # The names, in the order of the images
  @names [
    "octopus",
    "apple",
    "lemon",
    "carrot",
    "mushroom",
    "cactus",
    "sunflower",
    "maple leaf",
    "clover",
    "moon",
    "star",
    "sun",
    "lightning",
    "snowflake",
    "fire",
    "drop",
    "rainbow",
    "ladybug",
    "turtle",
    "dolphin",
    "butterfly",
    "penguin",
    "lion",
    "elephant",
    "owl",
    "dinosaur",
    "crab",
    "cat",
    "dog",
    "banana",
    "grapes",
    "cheese",
    "pizza",
    "ice cream",
    "lollipop",
    "cake",
    "balloon",
    "gift",
    "guitar",
    "die",
    "ball",
    "rocket",
    "anchor",
    "key",
    "light bulb",
    "alarm clock",
    "scissors",
    "magnet",
    "heart",
    "crown",
    "puzzle piece",
    "pencil",
    "bell",
    "target",
    "ghost",
    "snowman",
    "unicorn"
  ]

  @doc "The names of the symbols, by symbol."
  def names, do: @names

  @doc "The symbols of each card, as lists of 8 integers."
  def cards do
    n = @order
    infinity = n * n + n

    sloped =
      for m <- 0..(n - 1), b <- 0..(n - 1) do
        Enum.map(0..(n - 1), &(&1 * n + rem(m * &1 + b, n))) ++ [n * n + m]
      end

    vertical = for x <- 0..(n - 1), do: Enum.map(0..(n - 1), &(x * n + &1)) ++ [infinity]

    sloped ++ vertical ++ [Enum.to_list((n * n)..infinity)]
  end

  @doc """
  All cards in a random order, each with a random look: its symbols in a
  random order (the first one is in the middle, the others in a ring
  around it), a random size and rotation of each symbol, and a random turn
  of the ring. The ids are the places of the cards in `cards/0`.
  """
  def shuffled do
    cards()
    |> Enum.with_index(fn symbols, id ->
      %{
        id: id,
        symbols:
          symbols
          |> Enum.shuffle()
          |> Enum.map(fn symbol ->
            %{
              symbol: symbol,
              # From 0.6 to 1 of the room of the place
              size: Float.round(0.6 + :rand.uniform() * 0.4, 2),
              rotate: :rand.uniform(360) - 1
            }
          end),
        turn: :rand.uniform(360) - 1
      }
    end)
    |> Enum.shuffle()
  end

  @doc "The symbol that the two cards have in common."
  def common(a, b) do
    [symbol] = symbols(a) -- (symbols(a) -- symbols(b))
    symbol
  end

  defp symbols(card), do: Enum.map(card.symbols, & &1.symbol)
end
