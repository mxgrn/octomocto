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
    "nimble-mosaic" => Octomocto.NimbleMosaic.Result,
    "trains" => Octomocto.Trains.Result,
    "memory" => Octomocto.Memory.Result,
    "set" => Octomocto.SetGame.Result,
    "sudoku" => Octomocto.Sudoku.Result,
    "echo" => Octomocto.Echo.Result,
    "mahjong" => Octomocto.Mahjong.Result,
    "overlap" => Octomocto.Overlap.Result,
    "snap" => Octomocto.Snap.Result,
    "afterglow" => Octomocto.Afterglow.Result,
    "schulte" => Octomocto.Schulte.Result,
    "graze" => Octomocto.Graze.Result
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
  Gives the games played in each of the `days` days that end on `today`
  (the current day by default), `today` included.
  Each day is `%{date: date, total: n, by_game: %{game_id => n}}`, oldest
  first. A day without games has a total of 0.
  """
  def games_per_day(days, today \\ Date.utc_today()) do
    first = Date.add(today, 1 - days)

    counts =
      @results
      |> Enum.map(fn {game, schema} -> daily_counts(game, schema, first, today) end)
      |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
      |> Repo.all()
      |> Enum.group_by(& &1.date, &{&1.game, &1.count})

    for date <- Date.range(first, today) do
      by_game = counts |> Map.get(date, []) |> Map.new()
      %{date: date, total: by_game |> Map.values() |> Enum.sum(), by_game: by_game}
    end
  end

  defp daily_counts(game, schema, first, today) do
    from r in schema,
      where: r.inserted_at >= ^since(first) and r.inserted_at < ^until(today),
      group_by: fragment("?::date", r.inserted_at),
      select: %{
        game: type(^game, :string),
        date: fragment("?::date", r.inserted_at),
        count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
      }
  end

  @doc """
  Gives the games played in the `days` days that end on `today`, for each
  language of the players, the most played first. The language is the first
  part of the browser locale, for example "pt" for "pt-BR". Each item is
  `%{language: language, count: n, days: counts}`, with the counts in each
  day, oldest first. A game with players of two languages
  counts once for each language. The players without a known locale are not
  counted.
  """
  def games_by_language(days, today \\ Date.utc_today()) do
    first = Date.add(today, 1 - days)

    @results
    |> Map.values()
    |> Enum.map(&language_counts(&1, first, today))
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    # One row for each language and day, with the counts of all games added
    |> Enum.group_by(&{&1.language, &1.date}, & &1.count)
    |> Enum.map(fn {{language, date}, counts} ->
      %{language: language, date: date, count: Enum.sum(counts)}
    end)
    |> per_day(first, today, & &1.language)
    |> Enum.map(fn {language, counts} ->
      %{language: language, count: Enum.sum(counts), days: counts}
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  defp language_counts(schema, first, today) do
    from r in schema,
      left_join: u in User,
      on: u.id == r.user_id,
      left_join: g in Guest,
      on: g.id == r.guest_id,
      where: r.inserted_at >= ^since(first) and r.inserted_at < ^until(today),
      where: not is_nil(fragment("coalesce(?, ?)", u.locale, g.locale)),
      group_by: [
        fragment("split_part(coalesce(?, ?), '-', 1)", u.locale, g.locale),
        fragment("?::date", r.inserted_at)
      ],
      select: %{
        language: fragment("split_part(coalesce(?, ?), '-', 1)", u.locale, g.locale),
        date: fragment("?::date", r.inserted_at),
        count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
      }
  end

  @doc """
  The number of games in each of the `days` days that end on `today`,
  oldest first, in each game with players of the `language`, by the game
  id of the front page. The language is as in `games_by_language/2`, for
  example "pt". A game with no games in the language is not in the map.
  """
  def games_in_language(language, days, today \\ Date.utc_today()) do
    first = Date.add(today, 1 - days)

    @results
    |> Enum.map(fn {game, schema} ->
      from r in daily_counts(game, schema, first, today),
        left_join: u in User,
        on: u.id == r.user_id,
        left_join: g in Guest,
        on: g.id == r.guest_id,
        where: fragment("split_part(coalesce(?, ?), '-', 1)", u.locale, g.locale) == ^language
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> per_day(first, today)
  end

  @doc """
  The number of games of one player in each game, by the game id of the
  front page. The `field` is `:user_id` or `:guest_id`. A game with no
  results of the player is not in the map.
  """
  def games_of(field, id) when field in [:user_id, :guest_id] do
    @results
    |> Enum.map(fn {game, schema} ->
      from r in schema,
        where: field(r, ^field) == ^id,
        select: %{
          game: type(^game, :string),
          count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
        }
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> Enum.reject(&(&1.count == 0))
    |> Map.new(&{&1.game, &1.count})
  end

  @doc """
  The number of games of one player in each of the `days` days that end on
  `today`, by the game id of the front page. The `field` is `:user_id` or
  `:guest_id`. Each value is a list of `days` counts, oldest first. A game
  with no results of the player in these days is not in the map.
  """
  def games_per_day_of(field, id, days, today \\ Date.utc_today())
      when field in [:user_id, :guest_id] do
    first = Date.add(today, 1 - days)

    @results
    |> Enum.map(fn {game, schema} ->
      game |> daily_counts(schema, first, today) |> where([r], field(r, ^field) == ^id)
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> per_day(first, today)
  end

  # The rows of `daily_counts/3` as the counts in each day from `first` to
  # `today`, by the game id (or by another `key` of the rows)
  defp per_day(rows, first, today, key \\ & &1.game) do
    rows
    |> Enum.group_by(key, &{&1.date, &1.count})
    |> Map.new(fn {game, by_date} ->
      by_date = Map.new(by_date)
      {game, for(date <- Date.range(first, today), do: Map.get(by_date, date, 0))}
    end)
  end

  @doc """
  The time of the last finished game, in all games, of the user (`field`
  is `:user_id`) or the guest (`:guest_id`) `id`, or nil when it has none.
  """
  def last_played_of(field, id) when field in [:user_id, :guest_id] do
    @results
    |> Map.values()
    |> Enum.map(&from(r in &1, where: field(r, ^field) == ^id, select: max(r.inserted_at)))
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> Enum.reject(&is_nil/1)
    |> Enum.max(DateTime, fn -> nil end)
  end

  @doc """
  The game ids of the front page that the user (`field` is `:user_id`) or
  the guest (`:guest_id`) `id` played, the last played game first.
  """
  def recent_games_of(field, id) when field in [:user_id, :guest_id] do
    @results
    |> Enum.map(fn {game, schema} ->
      from r in schema,
        where: field(r, ^field) == ^id,
        select: %{game: type(^game, :string), at: max(r.inserted_at)}
    end)
    |> Enum.reduce(fn query, acc -> union_all(acc, ^query) end)
    |> Repo.all()
    |> Enum.reject(&is_nil(&1.at))
    |> Enum.sort_by(& &1.at, {:desc, DateTime})
    |> Enum.map(& &1.game)
  end

  @doc """
  The 10 players with the most games in the `days` days that end on
  `today`, in the game with the id `game` of the front page, the most
  games first. Each item is
  `%{user: user, guest: guest, count: n, days: counts}`, with a user or a
  guest and the other nil, and the counts of the player in each day, oldest
  first. Two players with the same count are in the order of their
  first game. The rows of a user count for the user, also when they have a
  guest id. The results of guests from before the guest ids have no
  player, so they are not counted.
  """
  def top_players(game, days, today \\ Date.utc_today()) do
    schema = Map.fetch!(@results, game)
    first = Date.add(today, 1 - days)

    rows =
      from(r in schema,
        where: r.inserted_at >= ^since(first) and r.inserted_at < ^until(today),
        where: not is_nil(r.user_id) or not is_nil(r.guest_id),
        group_by: [r.user_id, fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id)],
        order_by: [
          desc: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at)),
          asc: min(r.inserted_at)
        ],
        limit: 10,
        select: %{
          user_id: r.user_id,
          guest_id:
            type(fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id), Ecto.UUID),
          count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
        }
      )
      |> Repo.all()

    user_ids = rows |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1)
    guest_ids = rows |> Enum.map(& &1.guest_id) |> Enum.reject(&is_nil/1)
    users = by_id(User, user_ids)
    guests = by_id(Guest, guest_ids)
    per_day = players_per_day(schema, user_ids, guest_ids, first, today)

    Enum.map(rows, fn row ->
      %{
        user: users[row.user_id],
        guest: guests[row.guest_id],
        count: row.count,
        days: Map.fetch!(per_day, {row.user_id, row.guest_id})
      }
    end)
  end

  # The counts of the players in each day from `first` to `today`, by
  # `{user_id, guest_id}` as in `top_players/3`
  defp players_per_day(schema, user_ids, guest_ids, first, today) do
    from(r in schema,
      where: r.inserted_at >= ^since(first) and r.inserted_at < ^until(today),
      where: r.user_id in ^user_ids or (is_nil(r.user_id) and r.guest_id in ^guest_ids),
      group_by: [
        r.user_id,
        fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id),
        fragment("?::date", r.inserted_at)
      ],
      select: %{
        player:
          {r.user_id,
           type(fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id), Ecto.UUID)},
        date: fragment("?::date", r.inserted_at),
        count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
      }
    )
    |> Repo.all()
    |> per_day(first, today, & &1.player)
  end

  defp by_id(schema, ids),
    do: from(s in schema, where: s.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})

  @doc "True when the game id of the front page has results."
  def game?(game), do: Map.has_key?(@results, game)

  # The start of the day `first` and the end of the day `today`, in UTC
  defp since(first), do: DateTime.new!(first, ~T[00:00:00], "Etc/UTC")
  defp until(today), do: today |> Date.add(1) |> since()
end
