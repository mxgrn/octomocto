defmodule Octomocto.Memory.Themes do
  @moduledoc """
  The card themes of the Memory game. The images of a theme are in
  `priv/static/images/memory/<name>/`, with the names `1.svg` to `<cards>.svg`.
  The cover card shows the theme in the theme picker and the lobby. It is
  card 1, unless the theme sets a different `cover`. The theme picker
  marks a theme with `new: true` as new. A theme with `hidden: true` is
  not in the theme picker and no new game gets it. It stays here for the
  games and the results that have it.
  """

  @themes [
    %{name: "sushi", title: "Sushi", cards: 50, cover: 2},
    %{name: "food", title: "Food", cards: 230, cover: 31},
    %{name: "desert", title: "Desert", cards: 50},
    %{name: "ocean", title: "Ocean", cards: 50, cover: 11},
    %{name: "monsters", title: "Monsters", cards: 100, cover: 4},
    %{name: "insects", title: "Insects", cards: 50},
    %{name: "eighties", title: "Eighties", cards: 40},
    %{name: "spring", title: "Spring", cards: 38},
    %{name: "flowers", title: "Flowers", cards: 50},
    %{name: "birds", title: "Birds", cards: 49},
    %{name: "pets", title: "Pets", cards: 50},
    %{name: "workout", title: "Workout", cards: 50, hidden: true},
    %{name: "animals", title: "Animals", cards: 50},
    %{name: "fairy_tales", title: "Fairy Tales", cards: 50},
    %{name: "ecology", title: "Ecology", cards: 50, hidden: true},
    %{name: "music", title: "Music", cards: 50},
    %{name: "halloween", title: "Halloween", cards: 48},
    %{name: "flags", title: "Flags", cards: 50, cover: 49},
    %{name: "cats", title: "Cats", cards: 50},
    %{name: "space", title: "Space", cards: 50}
  ]

  @doc "The themes that a new game can get, in the order of the theme picker."
  def list, do: Enum.reject(@themes, & &1[:hidden])

  @doc "Gives the theme with the name, also a hidden theme, or nil."
  def get(name), do: Enum.find(@themes, &(&1.name == name))

  @doc "True when a new game can get the theme with the name."
  def visible?(name), do: Enum.any?(list(), &(&1.name == name))

  @doc """
  The themes that have enough images for a field of `cards` cards in sets
  of `set` cards: each image can be in only one set of a field.
  """
  def for_field(set, cards), do: Enum.filter(list(), &(&1.cards * set >= cards))

  @doc """
  The theme for a new field: the `choice` when it has enough images, else
  a random theme with enough images. The choice "random" always gives a
  random theme.
  """
  def pick(choice, set, cards) do
    names = set |> for_field(cards) |> Enum.map(& &1.name)
    if choice in names, do: choice, else: Enum.random(names)
  end

  @doc "Gives the file name of the cover card of the theme with the name."
  def cover(name), do: "#{name |> get() |> Map.get(:cover, 1)}.svg"
end
