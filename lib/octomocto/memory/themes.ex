defmodule Octomocto.Memory.Themes do
  @moduledoc """
  The card themes of the Memory game. The images of a theme are in
  `priv/static/images/memory/<name>/`, with the names `1.svg` to `<cards>.svg`.
  The cover card shows the theme in the theme picker and the lobby. It is
  card 1, unless the theme sets a different `cover`. The theme picker
  marks a theme with `new: true` as new.
  """

  @themes [
    %{name: "sushi", title: "Sushi", cards: 50, new: true, cover: 2},
    %{name: "food", title: "Food", cards: 230, new: true, cover: 31},
    %{name: "desert", title: "Desert", cards: 50, new: true},
    %{name: "ocean", title: "Ocean", cards: 50, new: true, cover: 11},
    %{name: "monsters", title: "Monsters", cards: 100, new: true, cover: 4},
    %{name: "insects", title: "Insects", cards: 50, new: true},
    %{name: "eighties", title: "Eighties", cards: 40},
    %{name: "spring", title: "Spring", cards: 38},
    %{name: "flowers", title: "Flowers", cards: 50},
    %{name: "birds", title: "Birds", cards: 49},
    %{name: "pets", title: "Pets", cards: 50},
    %{name: "workout", title: "Workout", cards: 50},
    %{name: "animals", title: "Animals", cards: 50},
    %{name: "fairy_tales", title: "Fairy Tales", cards: 50},
    %{name: "ecology", title: "Ecology", cards: 50},
    %{name: "music", title: "Music", cards: 50},
    %{name: "halloween", title: "Halloween", cards: 48},
    %{name: "flags", title: "Flags", cards: 50, cover: 49},
    %{name: "cats", title: "Cats", cards: 50},
    %{name: "space", title: "Space", cards: 50}
  ]

  def list, do: @themes

  def default, do: "eighties"

  @doc "Gives the theme with the name, or nil."
  def get(name), do: Enum.find(@themes, &(&1.name == name))

  @doc "Gives the file name of the cover card of the theme with the name."
  def cover(name), do: "#{name |> get() |> Map.get(:cover, 1)}.svg"
end
