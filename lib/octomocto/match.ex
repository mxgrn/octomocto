defmodule Octomocto.Match do
  @moduledoc """
  Multiplayer memory game: find the matching pairs (or triplets) of cards.
  Each game is a `Octomocto.Match.Game` process on one node of the cluster,
  found by its id. A copy of its state is in `Octomocto.Match.Store`, so
  the game continues on another node when its node stops. Finished fields
  are saved as `Octomocto.Match.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Repo
  alias Octomocto.Match.{Game, Result, Store}

  @list_size 10

  @doc """
  Starts a new game and returns its id. The `config` has the `:theme`, the
  `:set` size (2 or 3), the number of `:cards`, the number of `:players`
  and `:public` (a public game is in `open_games/0`).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.Match.GameSupervisor, {Game, {id, config}})

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  The public games that wait for players, with the fewest free seats first,
  and the oldest game first when the free seats are the same. Each game is
  a `Octomocto.Match.Game.lobby_entry/1`.
  """
  def open_games do
    Store.all()
    # The game of a node that stopped is in the store until a player joins
    # it again. Nobody waits in it.
    |> Enum.filter(&GenServer.whereis(Game.via(&1.id)))
    |> Enum.map(&Game.lobby_entry/1)
    |> Enum.reject(&is_nil/1)
    |> sort_open_games()
  end

  @doc """
  Puts the new row of one game in a list of `open_games/0`. The `entry` is
  nil when the game left the list.
  """
  def put_open_game(games, id, entry) do
    games
    |> Enum.reject(&(&1.id == id))
    |> Enum.concat(List.wrap(entry))
    |> sort_open_games()
  end

  defp sort_open_games(games), do: Enum.sort_by(games, &{&1.seats_left, &1.created_at})

  @doc """
  Adds a player for the calling process. The player is removed some time
  after the process stops. Subscribe to `Game.topic(id)` first to get all
  updates. The `user_id` is nil for a guest. The `name` is the display
  name, or nil for a color name. When the game has all its players, the
  new process only watches, and the player id is nil.

  Give the `player_id` of a player that is still in the game to bind that
  player to the calling process again. Only give a player id that the
  caller can trust (see `OctomoctoWeb.MatchChannel`).

  Gives `{:error, :unavailable}` when the node of the game stopped a
  moment ago. Try again soon.
  """
  def join(id, user_id \\ nil, name \\ nil, player_id \\ nil) do
    GameProcess.join(Game, Store, Octomocto.Match.GameSupervisor, id, user_id, name, player_id)
  end

  @doc "The player turns a card face up. Only the player of the turn can."
  def flip(id, player_id, card_id) when is_integer(card_id) do
    GenServer.cast(Game.via(id), {:flip, player_id, card_id})
  end

  @doc "Starts a new field with the same settings and zero scores."
  def restart(id) do
    GenServer.cast(Game.via(id), :restart)
  end

  @doc """
  Saves one finished field. Each player is a map with `:user_id` (nil for a
  guest) and `:score`.
  """
  def save_results(game_id, settings, elapsed_ms, players) do
    now = DateTime.utc_now()

    rows =
      Enum.map(players, fn player ->
        %{
          game_id: game_id,
          settings: settings,
          elapsed_ms: elapsed_ms,
          user_id: player.user_id,
          score: player.score,
          inserted_at: now
        }
      end)

    Repo.insert_all(Result, rows)
  end

  @doc """
  Gives the leaderboard for the settings, for example
  `%{"set" => 2, "cards" => 16, "players" => 1}`: the latest games (with
  all players, the best score first) and the best result of each
  signed-in user (the fastest first).
  """
  def leaderboard(settings) do
    %{latest: latest_games(settings), best: best_results(settings)}
  end

  @doc """
  Gives the results of the scope's user for the settings: the latest
  results (the newest first, each with all players of its game, the user
  first) and the best result (nil when there are no results).
  """
  def user_results(%{user: user}, settings) do
    user_query =
      from(r in Result, where: r.settings == type(^settings, :map) and r.user_id == ^user.id)

    latest =
      from(r in user_query, order_by: [desc: r.inserted_at], limit: @list_size)
      |> Repo.all()

    players = game_players(Enum.map(latest, & &1.game_id))

    latest =
      Enum.map(latest, fn result ->
        {mine, others} = Enum.split_with(players[result.game_id], &(&1.id == result.id))
        %{result: result, players: mine ++ others}
      end)

    best =
      from(r in user_query, order_by: [asc: r.elapsed_ms, asc: r.inserted_at], limit: 1)
      |> Repo.one()

    %{latest: latest, best: best}
  end

  defp latest_games(settings) do
    game_ids =
      from(r in Result,
        where: r.settings == type(^settings, :map),
        group_by: r.game_id,
        order_by: [desc: max(r.inserted_at)],
        limit: @list_size,
        select: r.game_id
      )
      |> Repo.all()

    players = game_players(game_ids)

    Enum.map(game_ids, fn game_id ->
      [first | _] = players[game_id]
      %{game_id: game_id, elapsed_ms: first.elapsed_ms, players: players[game_id]}
    end)
  end

  # Gives the results of all players of the games, by game id, the best
  # score first.
  defp game_players(game_ids) do
    from(r in Result,
      where: r.game_id in ^game_ids,
      order_by: [desc: r.score],
      preload: :user
    )
    |> Repo.all()
    |> Enum.group_by(& &1.game_id)
  end

  defp best_results(settings) do
    best_of_each_user =
      from(r in Result,
        where: r.settings == type(^settings, :map) and not is_nil(r.user_id),
        distinct: r.user_id,
        order_by: [asc: r.user_id, asc: r.elapsed_ms, asc: r.inserted_at]
      )

    from(r in subquery(best_of_each_user),
      order_by: [asc: r.elapsed_ms, asc: r.inserted_at],
      limit: @list_size,
      preload: :user
    )
    |> Repo.all()
  end
end
