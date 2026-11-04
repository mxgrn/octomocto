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
    "overlap" => Octomocto.Overlap.Result,
    "snap" => Octomocto.Snap.Result,
    "afterglow" => Octomocto.Afterglow.Result
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
  The `limit` players with the most games of all time in the game with the
  id `game` of the front page, the most games first. Each item is
  `%{user: user, guest: guest, count: n}`, with a user or a guest and the
  other nil. Two players with the same count are in the order of their
  first game. The rows of a user count for the user, also when they have a
  guest id. The results of guests from before the guest ids have no
  player, so they are not counted.
  """
  def top_players(game, limit \\ 10) do
    schema = Map.fetch!(@results, game)

    rows =
      from(r in schema,
        where: not is_nil(r.user_id) or not is_nil(r.guest_id),
        group_by: [r.user_id, fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id)],
        order_by: [
          desc: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at)),
          asc: min(r.inserted_at)
        ],
        limit: ^limit,
        select: %{
          user_id: r.user_id,
          guest_id:
            type(fragment("CASE WHEN ? IS NULL THEN ? END", r.user_id, r.guest_id), Ecto.UUID),
          count: count(fragment("DISTINCT (?, ?)", r.game_id, r.inserted_at))
        }
      )
      |> Repo.all()

    users = by_id(User, rows |> Enum.map(& &1.user_id) |> Enum.reject(&is_nil/1))
    guests = by_id(Guest, rows |> Enum.map(& &1.guest_id) |> Enum.reject(&is_nil/1))

    Enum.map(rows, fn row ->
      %{user: users[row.user_id], guest: guests[row.guest_id], count: row.count}
    end)
  end

  defp by_id(schema, ids),
    do: from(s in schema, where: s.id in ^ids) |> Repo.all() |> Map.new(&{&1.id, &1})

  @doc "True when the game id of the front page has results."
  def game?(game), do: Map.has_key?(@results, game)

  defp since(first), do: DateTime.new!(first, ~T[00:00:00], "Etc/UTC")
end
