defmodule Octomocto.Trains.Campaign do
  @moduledoc """
  The Trains campaign: a list of levels for one signed-in player, from 4
  switches at the normal pace to 12 switches at the expert pace with 7
  trains per house, the hardest settings of the game. The full round runs,
  and a level unlocks when 90% or more of the trains of the level before
  it got home (see `pass_count/1`).

  The levels have a chapter for each pace from normal to expert. The easy
  pace is not in the campaign: it was too easy as a start. In a chapter
  the board grows. The first level of the next pace has a smaller board,
  but it is harder than the last level of the pace before it. Each level
  has 10 or more trains, so that the 90% rule permits at least one error.

  The order of the levels comes from a simulation on the layouts of the
  game. A model player needs some time to flip a switch, and more time to
  find the house of each new train (more with more houses). The difficulty
  of a level is the slowest flip time with which half of the rounds pass.
  Most levels are 2% to 7% harder than the level before them. The first
  expert level is 10% harder. The last level needs a player who is 2.9
  times faster than the first level does.

  More trains per house make a level longer and only a little harder: the
  easy start of the round, when the board is empty, is a smaller part of
  it. Some levels use this: they have the board of the level before them
  and more trains per house. Above 3 trains per house a level does not
  become harder for the model player. Thus the trains per house go up in
  steps on the last levels, so that the round does not become 3 times
  longer in one step.

  Some levels have a number of switches that the settings page does not
  have (for example 5, 7 or 9).

  The best round of each level is a `Octomocto.Trains.CampaignLevel` row.
  """

  import Ecto.Query

  alias Octomocto.Repo
  alias Octomocto.Trains
  alias Octomocto.Trains.CampaignLevel

  # {switches, pace, trains per house} for each level
  @levels [
    {4, "normal", 2},
    {4, "normal", 4},
    {5, "normal", 2},
    {5, "normal", 4},
    {6, "normal", 2},
    {7, "normal", 2},
    {9, "normal", 2},
    {10, "normal", 2},
    {11, "normal", 2},
    {12, "normal", 2},
    {6, "hard", 2},
    {7, "hard", 2},
    {8, "hard", 2},
    {10, "hard", 2},
    {11, "hard", 2},
    {12, "hard", 2},
    {12, "hard", 3},
    {6, "expert", 2},
    {7, "expert", 2},
    {7, "expert", 3},
    {8, "expert", 3},
    {9, "expert", 4},
    {10, "expert", 4},
    {11, "expert", 5},
    {12, "expert", 7}
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
