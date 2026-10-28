defmodule Octomocto.Stats do
  @moduledoc """
  The number of games played, from the saved results of all games. One game
  is one finished round: all rows of a round have the same `game_id` and
  `inserted_at`. A restart in the same room is a new round, so it is a new
  game. The days are in UTC.
  """
  import Ecto.Query

  alias Octomocto.Accounts.User
  alias Octomocto.Guests.Guest
  alias Octomocto.Repo

  # The result schema of each game, by the game id of the front page
  @results %{
    "schulte" => Octomocto.Schulte.Result,
    "trains" => Octomocto.Trains.Result,
    "memory" => Octomocto.Memory.Result,
    "set" => Octomocto.SetGame.Result,
    "sudoku" => Octomocto.Sudoku.Result,
    "echo" => Octomocto.Echo.Result,
    "mahjong" => Octomocto.Mahjong.Result,
    "overlap" => Octomocto.Overlap.Result
  }

  @topic "stats"

  @doc """
  Gives the number of all games played since the first results.
  """
  def games_played do
    @results
    |> Map.values()
    |> Enum.map(fn schema ->
      from r in schema, select: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> Enum.sum()
  end

  @doc """
  Subscribes the caller to `{:game_finished}`, sent once for each finished
  round of any game.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(Octomocto.PubSub, @topic)

  @doc "Tells the subscribers that one more round is finished, on all nodes."
  def broadcast_game_finished do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, @topic, {:game_finished})
  end

  @doc """
  Gives the games played in each of the last `days` days, today included.
  Each day is `%{date: date, total: n, by_game: %{game_id => n}}`, oldest
  first. A day without games has a total of 0.
  """
  def games_per_day(days, today \\ Date.utc_today()) do
    first = Date.add(today, 1 - days)
    since = since(first)

    counts =
      @results
      |> Enum.map(fn {game, schema} -> daily_counts(game, schema, since) end)
      |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
      |> Repo.all()
      |> Enum.group_by(& &1.date, &{&1.game, &1.count})

    for date <- Date.range(first, today) do
      by_game = counts |> Map.get(date, []) |> Map.new()
      %{date: date, total: by_game |> Map.values() |> Enum.sum(), by_game: by_game}
    end
  end

  defp daily_counts(game, schema, since) do
    from r in schema,
      where: r.inserted_at >= ^since,
      group_by: fragment("?::date", r.inserted_at),
      select: %{
        game: type(^game, :string),
        date: fragment("?::date", r.inserted_at),
        count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
      }
  end

  @doc """
  Gives the games played in the last `days` days, today included, for each
  language of the players, the most played first. The language is the first
  part of the browser locale, for example "pt" for "pt-BR". Each item is
  `%{language: language, count: n}`. A game with players of two languages
  counts once for each language. The players without a known locale are not
  counted.
  """
  def games_by_language(days, today \\ Date.utc_today()) do
    since = since(Date.add(today, 1 - days))

    @results
    |> Map.values()
    |> Enum.map(&language_counts(&1, since))
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> Enum.group_by(& &1.language, & &1.count)
    |> Enum.map(fn {language, counts} -> %{language: language, count: Enum.sum(counts)} end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp language_counts(schema, since) do
    from r in schema,
      left_join: u in User,
      on: u.id == r.user_id,
      left_join: g in Guest,
      on: g.id == r.guest_id,
      where: r.inserted_at >= ^since,
      where: not is_nil(fragment("coalesce(?, ?)", u.locale, g.locale)),
      group_by: fragment("split_part(coalesce(?, ?), '-', 1)", u.locale, g.locale),
      select: %{
        language: fragment("split_part(coalesce(?, ?), '-', 1)", u.locale, g.locale),
        count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
      }
  end

  defp since(first), do: DateTime.new!(first, ~T[00:00:00], "Etc/UTC")
end
