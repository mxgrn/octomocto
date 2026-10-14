defmodule Octomocto.SetGame do
  @moduledoc """
  Multiplayer Set: find 3 cards where each attribute is the same on all
  cards or different on all cards. Each game is a `Octomocto.SetGame.Game`
  process on one node of the cluster, found by its id. A copy of its state
  is in `Octomocto.SetGame.Store`, so the game continues on another node
  when its node stops. Finished tables are saved as
  `Octomocto.SetGame.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Repo
  alias Octomocto.SetGame.{Game, Result, Store}

  @list_size 10

  @doc """
  Starts a new game and returns its id. The `config` has the number of
  `:players` and `:public` (a public game is in the lists of the settings
  page).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.SetGame.GameSupervisor, {Game, {id, config}})

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  Adds a player for the calling process. The player is removed some time
  after the process stops. Subscribe to `Game.topic(id)` first to get all
  updates. The `user_id` is nil for a guest. The `name` is the display
  name, or nil for a color name. When the game has all its players, the
  new process only watches, and the player id is nil.

  Give the `player_id` of a player that is still in the game to bind that
  player to the calling process again. Only give a player id that the
  caller can trust (see `OctomoctoWeb.SetGameChannel`).

  Gives `{:error, :unavailable}` when the node of the game stopped a
  moment ago. Try again soon.
  """
  def join(id, user_id \\ nil, name \\ nil, player_id \\ nil) do
    GameProcess.join(Game, Store, Octomocto.SetGame.GameSupervisor, id, user_id, name, player_id)
  end

  @doc """
  Gives the state of the game to a process that only watches, also when the
  game has a free seat. Subscribe to `Game.topic(id)` first to get all
  updates. Gives the same errors as `join/4`.
  """
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.SetGame.GameSupervisor, id)
  end

  @doc "The player claims that the 3 cards are a set. The first player with a set gets it."
  def claim(id, player_id, cards) when is_list(cards) do
    GenServer.cast(Game.via(id), {:claim, player_id, cards})
  end

  @doc "Starts a new table with zero scores. Only a player can."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  Saves one finished table. Each player is a map with `:user_id` (nil for a
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
  `%{"mode" => "normal", "players" => 1}`: the latest games (with
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
