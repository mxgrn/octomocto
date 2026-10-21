defmodule Octomocto.Memory.Campaign do
  @moduledoc """
  The Memory campaign: a list of levels for one signed-in player, from a
  small field of pairs to 100 cards. Pairs and triplets take turns. A level
  unlocks when the player clears the level before it with no slip: the game
  stops at the first error (see `Octomocto.Memory.Game`). Thus luck does
  not help: only the flips where the player can know the answer count.

  The order of the levels comes from a simulation. The difficulty of a
  field is the sum of the cards that a player must remember over all the
  counted flips. A field of N triplets is about as hard as a field of
  1.4 × N pairs. The first field of triplets is only a little harder than
  the field before it, because the new rule is the step.

  The best run of each level is a `Octomocto.Memory.CampaignLevel` row.
  """

  import Ecto.Query

  alias Octomocto.Memory
  alias Octomocto.Memory.{CampaignLevel, Themes}
  alias Octomocto.Repo

  # {set, cards} for each level
  @levels [
    {2, 8},
    {2, 12},
    {2, 16},
    {3, 12},
    {2, 20},
    {3, 15},
    {2, 24},
    {3, 18},
    {2, 30},
    {3, 21},
    {2, 36},
    {3, 27},
    {2, 42},
    {3, 30},
    {2, 50},
    {3, 36},
    {2, 60},
    {3, 42},
    {2, 72},
    {3, 54},
    {2, 84},
    {3, 63},
    {2, 100}
  ]

  @leaderboard_size 10

  @doc "The levels, each with its `:level` number (from 1), `:set` and `:cards`."
  def levels do
    @levels
    |> Enum.with_index(1)
    |> Enum.map(fn {{set, cards}, level} -> %{level: level, set: set, cards: cards} end)
  end

  def count, do: length(@levels)

  @doc "The level with the number, or nil."
  def get(level) when is_integer(level), do: Enum.at(levels(), level - 1)

  @doc """
  The themes that have enough images for the level: each image can be in
  only one set of a field.
  """
  def themes(%{set: set, cards: cards}) do
    Enum.filter(Themes.list(), &(&1.cards * set >= cards))
  end

  @doc """
  The theme for a new field of the level: the `choice` when it has enough
  images, else a random theme. The choice "random" always gives a random
  theme.
  """
  def pick_theme(level, choice) do
    names = level |> themes() |> Enum.map(& &1.name)
    if choice in names, do: choice, else: Enum.random(names)
  end

  @doc "The best runs of the user, by level number."
  def progress(user_id) do
    from(l in CampaignLevel, where: l.user_id == ^user_id)
    |> Repo.all()
    |> Map.new(&{&1.level, &1})
  end

  @doc "The highest level with no slip in the `progress/1`, or 0."
  def highest(progress) do
    progress
    |> Map.values()
    |> Enum.filter(& &1.completed_at)
    |> Enum.map(& &1.level)
    |> Enum.max(fn -> 0 end)
  end

  @doc "True when the player can play the level: the first one, or the level after a completed one."
  def unlocked?(progress, level), do: level >= 1 and level <= highest(progress) + 1

  @doc """
  Starts a game of the level for the user, and gives `{:ok, game_id}`, or
  `{:error, :locked}` when the user cannot play the level yet. The theme
  `choice` is a theme name or "random", see `pick_theme/2`.
  """
  def start(user_id, level_number, choice) do
    level = get(level_number)

    if level && unlocked?(progress(user_id), level_number) do
      theme = pick_theme(level, choice)

      id =
        Memory.create_game(%{
          theme: theme,
          set: level.set,
          cards: level.cards,
          players: 1,
          # Others can watch it in the ongoing games, see `Octomocto.Lobby`
          public: true,
          campaign: %{level: level_number, user_id: user_id, theme: choice}
        })

      {:ok, id}
    else
      {:error, :locked}
    end
  end

  @doc """
  Saves a finished run of the level: the user cleared `cleared` cards
  before a slip, or all cards. Keeps the best run of the user.
  """
  def save_run(user_id, level_number, cleared) do
    now = DateTime.utc_now()
    completed_at = if cleared == get(level_number).cards, do: now

    Repo.insert_all(
      CampaignLevel,
      [
        %{
          user_id: user_id,
          level: level_number,
          best_cleared: cleared,
          completed_at: completed_at,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        from(l in CampaignLevel,
          update: [
            set: [
              best_cleared: fragment("GREATEST(?, EXCLUDED.best_cleared)", l.best_cleared),
              completed_at: fragment("COALESCE(?, EXCLUDED.completed_at)", l.completed_at),
              updated_at: fragment("EXCLUDED.updated_at")
            ]
          ]
        ),
      conflict_target: [:user_id, :level]
    )
  end

  @doc """
  The users with the highest levels: the highest completed level of each
  user, and the time when the user completed it. Who got there first is
  higher.
  """
  def leaderboard do
    highest_of_each_user =
      from(l in CampaignLevel,
        where: not is_nil(l.completed_at),
        distinct: l.user_id,
        order_by: [asc: l.user_id, desc: l.level]
      )

    from(l in subquery(highest_of_each_user),
      order_by: [desc: l.level, asc: l.completed_at],
      limit: @leaderboard_size,
      preload: :user
    )
    |> Repo.all()
  end
end
