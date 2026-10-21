defmodule Octomocto.Trains.Campaign do
  @moduledoc """
  The Trains campaign: a list of levels for one signed-in player, from 3
  switches (4 houses) at the easy pace to 12 switches at the expert pace. The full
  round runs, and a level unlocks when 90% or more of the trains of the
  level before it got home (see `pass_count/1`).

  The order of the levels comes from a simulation on the layouts of the
  game. A model player needs some time to flip a switch, and more time to
  find the house of each new train (more with more houses). The difficulty
  of a level is the slowest flip time that still gets 90% of the trains
  home. Each level is 3% to 13% harder than the level before it. A faster
  pace is about as hard as 2 to 4 more switches.

  Some levels have 3 or 7 switches, which the settings page does not have.

  The best round of each level is a `Octomocto.Trains.CampaignLevel` row.
  """

  import Ecto.Query

  alias Octomocto.Repo
  alias Octomocto.Trains
  alias Octomocto.Trains.CampaignLevel

  # {switches, pace, trains per house} for each level
  @levels [
    {3, "easy", 2},
    {4, "easy", 2},
    {6, "easy", 2},
    {8, "easy", 2},
    {12, "easy", 2},
    {4, "normal", 2},
    {4, "normal", 3},
    {6, "normal", 2},
    {4, "hard", 2},
    {7, "normal", 2},
    {8, "normal", 2},
    {6, "hard", 2},
    {12, "normal", 2},
    {7, "hard", 2},
    {6, "expert", 2},
    {8, "hard", 2},
    {12, "hard", 2},
    {8, "expert", 2},
    {12, "expert", 2},
    {12, "expert", 3}
  ]

  @leaderboard_size 10

  @doc """
  The levels, each with its `:level` number (from 1), `:switch_count`,
  `:pace`, `:trains_per_house` and number of `:trains`.
  """
  def levels do
    @levels
    |> Enum.with_index(1)
    |> Enum.map(fn {{switches, pace, per_house}, level} ->
      %{
        level: level,
        switch_count: switches,
        pace: pace,
        trains_per_house: per_house,
        trains: per_house * (switches + 1)
      }
    end)
  end

  def count, do: length(@levels)

  @doc "The level with the number, or nil."
  def get(level) when is_integer(level), do: Enum.at(levels(), level - 1)

  @doc "The number of trains that must get home to pass a level with the trains: 90%, rounded up."
  def pass_count(trains), do: div(9 * trains + 9, 10)

  @doc "The best rounds of the user, by level number."
  def progress(user_id) do
    from(l in CampaignLevel, where: l.user_id == ^user_id)
    |> Repo.all()
    |> Map.new(&{&1.level, &1})
  end

  @doc "The highest passed level in the `progress/1`, or 0."
  def highest(progress) do
    progress
    |> Map.values()
    |> Enum.filter(& &1.completed_at)
    |> Enum.map(& &1.level)
    |> Enum.max(fn -> 0 end)
  end

  @doc "True when the player can play the level: the first one, or the level after a passed one."
  def unlocked?(progress, level), do: level >= 1 and level <= highest(progress) + 1

  @doc """
  Starts a game of the level for the user, and gives `{:ok, game_id}`, or
  `{:error, :locked}` when the user cannot play the level yet.
  """
  def start(user_id, level_number) do
    level = get(level_number)

    if level && unlocked?(progress(user_id), level_number) do
      id =
        Trains.create_game(%{
          players: 1,
          switch_count: level.switch_count,
          trains_per_house: level.trains_per_house,
          pace: level.pace,
          # Others can watch it in the ongoing games, see `Octomocto.Lobby`
          public: true,
          campaign: %{level: level_number, user_id: user_id}
        })

      {:ok, id}
    else
      {:error, :locked}
    end
  end

  @doc """
  Saves a finished round of the level: `correct` trains got home. Keeps the
  best round of the user.
  """
  def save_run(user_id, level_number, correct) do
    now = DateTime.utc_now()
    completed_at = if correct >= pass_count(get(level_number).trains), do: now

    Repo.insert_all(
      CampaignLevel,
      [
        %{
          user_id: user_id,
          level: level_number,
          best_correct: correct,
          completed_at: completed_at,
          inserted_at: now,
          updated_at: now
        }
      ],
      on_conflict:
        from(l in CampaignLevel,
          update: [
            set: [
              best_correct: fragment("GREATEST(?, EXCLUDED.best_correct)", l.best_correct),
              completed_at: fragment("COALESCE(?, EXCLUDED.completed_at)", l.completed_at),
              updated_at: fragment("EXCLUDED.updated_at")
            ]
          ]
        ),
      conflict_target: [:user_id, :level]
    )
  end

  @doc """
  The users with the highest levels: the highest passed level of each
  user, and the time when the user passed it. Who got there first is
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
