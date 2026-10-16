defmodule Octomocto.Mahjong.Board do
  @moduledoc """
  The Turtle layout of mahjong solitaire, the 144 faces, and the deal.

  A position is `{layer, col, row}`. The `col` and the `row` are in half
  tiles, so that a tile is 2 columns wide and 2 rows high, and a tile can
  sit between two others (for example, the top of the Turtle). The layer 0
  is the bottom.

  A tile is free when no tile lies on it, and its left side or its right
  side touches no tile of the same layer. Two free tiles with the same
  face go off the board as a pair. Any flower matches any flower, and any
  season matches any season.

  The deal always has a solution: it takes free positions of the full
  layout two by two, and gives each two the faces of a pair. The players
  remove the tiles in the reverse order of the deal, so each pair is free
  when it comes. Bad picks can still leave a board with no free pair. Then
  `shuffle/1` deals the faces of the tiles that are left again, in the
  same way.
  """

  @suits for suit <- ~w(dots bamboo chars), n <- 1..9, do: "#{suit}-#{n}"
  @honors ~w(wind-e wind-s wind-w wind-n dragon-r dragon-g dragon-w)
  @bonus for kind <- ~w(flower season), n <- 1..4, do: "#{kind}-#{n}"

  # 4 tiles of each suit and honor face, and 1 tile of each bonus face
  @faces Enum.flat_map(@suits ++ @honors, &List.duplicate(&1, 4)) ++ @bonus

  # Tiles in each row of the layer 0, from the top: the first column and the
  # number of tiles, in whole tiles
  @bottom_rows [{1, 12}, {3, 8}, {2, 10}, {1, 12}, {1, 12}, {2, 10}, {3, 8}, {1, 12}]

  # One tile on the left end and two on the right end, between the
  # two middle rows
  # The top, between the 4 tiles of the layer 3
  @turtle for(
            {{first, count}, y} <- Enum.with_index(@bottom_rows),
            x <- first..(first + count - 1),
            do: {0, 2 * x, 2 * y}
          ) ++
            [{0, 0, 7}, {0, 26, 7}, {0, 28, 7}] ++
            for(
              {layer, from, to} <- [{1, 4, 9}, {2, 5, 8}, {3, 6, 7}],
              x <- from..to,
              y <- (from - 3)..(to - 3),
              do: {layer, 2 * x, 2 * y}
            ) ++
            [{4, 13, 7}]

  @attempts 50

  @doc "The 144 positions of the Turtle layout"
  def turtle, do: @turtle

  @doc "The size of the layout in half tiles: `{cols, rows}`"
  def size, do: {30, 16}

  @doc """
  Deals the 144 faces on the Turtle. Gives a map from the tile id (0 to
  143) to `%{face: face, pos: position}`.
  """
  def deal do
    tiles = @turtle |> Enum.with_index() |> Map.new(fn {pos, id} -> {id, %{pos: pos}} end)
    shuffle(tiles, @faces)
  end

  @doc """
  Mixes the tiles, so that they have a solution. Each tile keeps its id and
  its face, and moves to a new position, as when players mix real tiles. A
  set of positions with no solution (for example, a tile on the last other
  tile) goes to the layer 0.
  """
  def shuffle(tiles) do
    dealt = shuffle(tiles, Enum.map(tiles, fn {_id, tile} -> tile.face end))
    # The positions that got each face
    places = dealt |> Map.values() |> Enum.group_by(& &1.face, & &1.pos)

    tiles
    |> Enum.shuffle()
    |> Enum.map_reduce(places, fn {id, tile}, places ->
      [pos | rest] = places[tile.face]
      {{id, %{tile | pos: pos}}, Map.put(places, tile.face, rest)}
    end)
    |> elem(0)
    |> Map.new()
  end

  defp shuffle(tiles, faces) do
    pairs = faces |> Enum.group_by(&match_key/1) |> Enum.flat_map(&pairs/1)

    case deal_pairs(tiles, pairs, @attempts) do
      {:ok, dealt} -> dealt
      :error -> tiles |> flatten() |> deal_pairs(pairs, @attempts) |> elem(1)
    end
  end

  # The faces of one match key, two by two, in a random order
  defp pairs({_key, faces}) do
    faces |> Enum.shuffle() |> Enum.chunk_every(2)
  end

  defp deal_pairs(tiles, pairs, attempts) do
    Enum.find_value(1..attempts, :error, fn _attempt ->
      case take_pairs(Map.keys(tiles), positions(tiles), Enum.shuffle(pairs), %{}) do
        {:ok, faces} ->
          {:ok, Map.new(tiles, fn {id, t} -> {id, Map.put(t, :face, faces[id])} end)}

        :error ->
          nil
      end
    end)
  end

  # Takes two random free tiles for each pair, as if the players removed
  # them, until no tile is left
  defp take_pairs([], _positions, [], faces), do: {:ok, faces}

  defp take_pairs(ids, positions, [[face_a, face_b] | pairs], faces) do
    case ids |> Enum.filter(&free?(positions[&1], positions)) |> Enum.shuffle() do
      [a, b | _] ->
        positions = Map.drop(positions, [a, b])
        faces = Map.merge(faces, %{a => face_a, b => face_b})
        take_pairs(ids -- [a, b], positions, pairs, faces)

      _ ->
        :error
    end
  end

  # Moves the tiles to the layer 0 positions of the Turtle, which always
  # have a solution: each row has a free tile at each end.
  defp flatten(tiles) do
    bottom = Enum.filter(@turtle, &match?({0, _, _}, &1))

    tiles
    |> Enum.sort()
    |> Enum.zip(bottom)
    |> Map.new(fn {{id, tile}, pos} -> {id, %{tile | pos: pos}} end)
  end

  @doc "The positions of the tiles by id"
  def positions(tiles), do: Map.new(tiles, fn {id, tile} -> {id, tile.pos} end)

  @doc "True when no tile lies on the tile, and its left or right side is open"
  def free?({layer, col, row}, positions) do
    others = Map.values(positions)

    covered? =
      Enum.any?(others, fn {l, c, r} ->
        l == layer + 1 and abs(c - col) < 2 and abs(r - row) < 2
      end)

    side? = fn dc ->
      Enum.any?(others, fn {l, c, r} -> l == layer and c == col + dc and abs(r - row) < 2 end)
    end

    not covered? and not (side?.(-2) and side?.(2))
  end

  @doc "True when two faces make a pair"
  def pair?(a, b), do: match_key(a) == match_key(b)

  defp match_key("flower-" <> _), do: "flower"
  defp match_key("season-" <> _), do: "season"
  defp match_key(face), do: face

  @doc "True when at least one pair of free tiles has the same face"
  def free_pair?(tiles) do
    positions = positions(tiles)

    tiles
    |> Enum.filter(fn {_id, tile} -> free?(tile.pos, positions) end)
    |> Enum.group_by(fn {_id, tile} -> match_key(tile.face) end)
    |> Enum.any?(fn {_key, group} -> length(group) > 1 end)
  end
end
