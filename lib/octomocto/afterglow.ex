defmodule Octomocto.Afterglow do
  @moduledoc """
  Afterglow: a game where the player remembers which tiles of a grid lit
  up (see `Octomocto.Afterglow.Game`). The game with turns for 2 to 4
  players is in `Octomocto.Afterglow.Turns`. Each game is a
  `Octomocto.Afterglow.Game` process on one node of the cluster, found by
  its id. A copy of its state is in `Octomocto.Afterglow.Store`, so the
  game continues on another node when its node stops. Finished games are
  saved as `Octomocto.Afterglow.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.Afterglow.{Game, Result, Store}
  alias Octomocto.GameProcess
  alias Octomocto.Repo

  @list_size 5

  @doc """
  Starts a new game and returns its id. The `config` has `:start_level`,
  the tiles of the first round (see `last_level/2`).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    config = Map.merge(config, %{players: 1, public: false})

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.Afterglow.GameSupervisor, {Game, {id, config}})

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  Adds the player for the calling process, see `Octomocto.Overlap.join/5`.
  A second browser only watches.
  """
  def join(
        id,
        user_id \\ nil,
        name \\ nil,
        player_id \\ nil,
        guest_id \\ nil,
        from_lobby \\ false
      ) do
    GameProcess.join(
      Game,
      Store,
      Octomocto.Afterglow.GameSupervisor,
      id,
      user_id,
      name,
      player_id,
      guest_id,
      from_lobby
    )
  end

  @doc "Gives the state of the game to a process that only watches."
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.Afterglow.GameSupervisor, id)
  end

  @doc "The player clicks the `cell` of the grid in the `round`. Only the current round counts."
  def tap(id, player_id, round, cell) do
    GenServer.cast(Game.via(id), {:tap, player_id, round, cell})
  end

  @doc "Starts a new game with a zero score. Only the player can."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  The tiles of the last round of the last game of the user (or of the
  guest, when the user id is nil), where the next game starts. Nil before
  the first game.
  """
  def last_level(nil, nil), do: nil

  def last_level(user_id, guest_id) do
    # Only the single-player games have rounds
    solo = from(r in Result, where: r.settings == type(^%{"players" => 1}, :map))

    query =
      if user_id,
        do: from(r in solo, where: r.user_id == ^user_id),
        else: from(r in solo, where: r.guest_id == ^guest_id)

    from(r in query, order_by: [desc: r.inserted_at], limit: 1, select: r.last_level)
    |> Repo.one()
  end

  @doc """
  Saves one finished game. The player is a map with `:user_id` (nil for a
  guest), `:name`, `:guest_id` (see `Octomocto.Guests`), `:score`,
  `:best_level`, `:last_level` (nil in a game with turns) and `:perfect`.
  """
  def save_results(game_id, settings, _elapsed_ms, players) do
    now = DateTime.utc_now()

    rows =
      Enum.map(players, fn player ->
        %{
          game_id: game_id,
          settings: settings,
          user_id: player.user_id,
          guest_id: Octomocto.Guests.guest_id(player),
          score: player.score,
          best_level: player.best_level,
          last_level: player.last_level,
          perfect: player.perfect,
          inserted_at: now
        }
      end)

    Octomocto.Guests.save(players, now)

    Octomocto.Notifications.watch_top(__MODULE__, "afterglow", settings, players, fn ->
      Repo.insert_all(Result, rows)
    end)

    Octomocto.Locales.broadcast_saved(players)
    Octomocto.Stats.broadcast_game_finished()
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
      from(r in user_query, order_by: [desc: r.score, asc: r.inserted_at], limit: 1)
      |> Repo.one()

    %{latest: latest, best: best}
  end

  # Gives the results of all players of the games, by game id, the best
  # score first. The game id of a game with turns is the id of its field.
  defp game_players(game_ids) do
    from(r in Result,
      where: r.game_id in ^game_ids,
      order_by: [desc: r.score],
      preload: [:user, :guest]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.game_id)
  end

  @doc """
  Gives the best result of each signed-in user for the settings (the
  highest score first).
  With `user_ids`, only the results of these users (see
  `Octomocto.ResultQueries.of_users/2`).
  """
  def best_results(settings, user_ids \\ nil) do
    best_of_each_user =
      from(r in Result,
        where: r.settings == type(^settings, :map) and not is_nil(r.user_id),
        distinct: r.user_id,
        order_by: [asc: r.user_id, desc: r.score, asc: r.inserted_at]
      )
      |> Octomocto.ResultQueries.of_users(user_ids)

    from(r in subquery(best_of_each_user),
      order_by: [desc: r.score, asc: r.inserted_at],
      limit: @list_size,
      preload: :user
    )
    |> Repo.all()
  end
end
