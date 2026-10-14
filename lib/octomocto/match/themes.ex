defmodule Octomocto.Match.Themes do
  @moduledoc """
  The card themes of the Match game. The images of a theme are in
  `priv/static/images/match/<name>/`, with the names `1.svg` to `<cards>.svg`.
  """

  @themes [
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
    %{name: "flags", title: "Flags", cards: 50}
  ]

  def list, do: @themes

  def default, do: hd(@themes).name

  @doc "Gives the theme with the name, or nil."
  def get(name), do: Enum.find(@themes, &(&1.name == name))
end
