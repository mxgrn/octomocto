defmodule Octomocto.Overlap.Themes do
  @moduledoc """
  The symbol themes of Overlap. Each theme has 57 symbols, one for each
  point of the plane (see `Octomocto.Overlap.Deck`). The images of a theme
  are in `priv/static/images/overlap/<name>/`, with the names `0.svg` to
  `56.svg`, in the order of the `names`. The names are for the screen
  readers. The `cover` symbol shows the theme in the theme picker and in
  the lobby. The themes are mixes of all kinds of symbols, and no symbol is
  in two themes.

  The images are Twemoji (CC-BY 4.0, Twitter, Inc. and other contributors,
  https://github.com/jdecked/twemoji).
  """

  @themes [
    %{
      name: "mix1",
      title: "Mix 1",
      cover: 0,
      names: [
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
    },
    %{
      name: "mix2",
      title: "Mix 2",
      cover: 53,
      names: [
        "fox",
        "frog",
        "bee",
        "snail",
        "shark",
        "giraffe",
        "zebra",
        "parrot",
        "chicken",
        "snake",
        "panda",
        "koala",
        "strawberry",
        "watermelon",
        "peach",
        "avocado",
        "corn",
        "hamburger",
        "doughnut",
        "cookie",
        "cupcake",
        "egg",
        "tulip",
        "fir tree",
        "wave",
        "volcano",
        "cloud",
        "globe",
        "top hat",
        "glasses",
        "sneaker",
        "backpack",
        "camera",
        "telephone",
        "magnifier",
        "lock",
        "books",
        "umbrella",
        "palette",
        "drum",
        "trumpet",
        "basketball",
        "trophy",
        "car",
        "bicycle",
        "airplane",
        "helicopter",
        "sailboat",
        "hundred",
        "stop sign",
        "recycling",
        "music note",
        "alien",
        "robot",
        "teddy bear",
        "crystal ball",
        "compass"
      ]
    },
    %{
      name: "mix3",
      title: "Mix 3",
      cover: 0,
      names: [
        "raccoon",
        "rabbit",
        "pig",
        "cow",
        "monkey",
        "eagle",
        "duck",
        "crocodile",
        "tropical fish",
        "whale",
        "peacock",
        "spider",
        "cherries",
        "pineapple",
        "coconut",
        "broccoli",
        "hot pepper",
        "croissant",
        "pretzel",
        "taco",
        "sushi",
        "popcorn",
        "hibiscus",
        "palm tree",
        "comet",
        "shell",
        "mountain",
        "seedling",
        "cap",
        "high heel",
        "ring",
        "television",
        "laptop",
        "flashlight",
        "hammer",
        "telescope",
        "broom",
        "kite",
        "violin",
        "tennis",
        "bowling",
        "skateboard",
        "microphone",
        "locomotive",
        "bus",
        "flying saucer",
        "tractor",
        "ship",
        "gem",
        "money bag",
        "skull",
        "jack-o-lantern",
        "christmas tree",
        "firecracker",
        "bomb",
        "castle",
        "house"
      ]
    }
  ]

  @default "mix1"

  @doc "The themes, in the order of the theme picker."
  def list, do: @themes

  @doc "The theme of a game when the settings do not choose one."
  def default, do: @default

  @doc "Gives the theme with the name, or nil."
  def get(name), do: Enum.find(@themes, &(&1.name == name))

  @doc "True when a theme has the name. The choice \"random\" is not a theme."
  def exists?(name), do: get(name) != nil

  @doc """
  The theme for a new deck: the `choice` when it is a theme, else a random
  theme. The choice "random" always gives a random theme.
  """
  def pick(choice) do
    if exists?(choice), do: choice, else: Enum.random(@themes).name
  end

  @doc "The names of the symbols of each theme by the theme name."
  def names, do: Map.new(@themes, &{&1.name, &1.names})
end
