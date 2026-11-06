defmodule Octomocto.Graze do
  @moduledoc """
  Games of Graze: circles that eat food squares and keep away from danger
  squares in one shared field. Each game is a `Octomocto.Graze.Game`
  process on one node of the cluster, found by its id. A copy of its state
  is in `Octomocto.Graze.Store`, so the game continues on another node
  when its node stops. Finished fields are saved as `Octomocto.Graze.Result`
  rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Graze.{Game, Result, Store}
  alias Octomocto.Repo

  @list_size 5

  @doc """
  Starts a new game for the given number of players, and returns its id. A
  `public` game is in the lists of the settings page (see
  `Octomocto.Lobby`). A game with `creator` false has no creator (see
  `Octomocto.Seats`).
  """
  def create_game(players, public, creator \\ true) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Octomocto.Graze.GameSupervisor,
        {Game, {id, %{players: players, public: public, creator: creator}}}
      )

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  Adds a player for the calling process, see `Octomocto.Schulte.join/6`.
  The arguments and the errors are the same.
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
      Octomocto.Graze.GameSupervisor,
      id,
      user_id,
      name,
      player_id,
      guest_id,
      from_lobby
    )
  end

  @doc """
  Gives the state of the game to a process that only watches. Subscribe to
  `Game.topic(id)` first to get all updates. Gives the same errors as
  `join/6`.
  """
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.Graze.GameSupervisor, id)
  end

  @doc """
  The circle of the player is at `x`, `y` at the time `t` of the field (the
  system time in milliseconds). See `Octomocto.Graze.Game`.
  """
  def steer(id, player_id, x, y, t) do
    GenServer.cast(Game.via(id), {:steer, player_id, x, y, t})
  end

  @doc "Starts a new field with zero scores. Only a player can."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  Saves one finished field. Each player is a map with `:user_id` (nil for a
  guest), `:name`, `:guest_id` (see `Octomocto.Guests`), `:score` and the
  time of the circle in the field (`:survived_ms`). The time of the whole
  field (`_elapsed_ms`) is not saved: it is the time of the best circle.
  """
  def save_results(game_id, settings, _elapsed_ms, players) do
    now = DateTime.utc_now()

    rows =
      Enum.map(players, fn player ->
        %{
          game_id: game_id,
          settings: settings,
          elapsed_ms: player.survived_ms,
          user_id: player.user_id,
          guest_id: Octomocto.Guests.guest_id(player),
          score: player.score,
          inserted_at: now
        }
      end)

    Octomocto.Guests.save(players, now)
    Repo.insert_all(Result, rows)
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
      from(r in without_guests(user_query), order_by: ^best_order(), limit: 1)
      |> Repo.one()

    %{latest: latest, best: best}
  end

  # Gives the results of all players of the games, by game id, the best
  # score first.
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
  highest score first). With `user_ids`, only the results of these users
  (see `Octomocto.ResultQueries.of_users/2`).
  """
  def best_results(settings, user_ids \\ nil) do
    best_of_each_user =
      from(r in without_guests(Result),
        where: r.settings == type(^settings, :map) and not is_nil(r.user_id),
        distinct: r.user_id,
        order_by: [asc: r.user_id, desc: r.score, desc: r.elapsed_ms, asc: r.inserted_at]
      )
      |> Octomocto.ResultQueries.of_users(user_ids)

    from(r in subquery(best_of_each_user),
      order_by: ^best_order(),
      limit: @list_size,
      preload: :user
    )
    |> Repo.all()
  end

  # The highest score first. With the same score, the longer time in the
  # field, then the earlier result.
  defp best_order, do: [desc: :score, desc: :elapsed_ms, asc: :inserted_at]

  # Keeps the results of the fields where all players were signed in. The
  # rows of one field have the same game id and time (see `save_results`).
  defp without_guests(query) do
    guests =
      from(g in Result,
        where:
          g.game_id == parent_as(:result).game_id and
            g.inserted_at == parent_as(:result).inserted_at and is_nil(g.user_id)
      )

    from(r in query, as: :result, where: not exists(guests))
  end
end
