defmodule Octomocto.Schulte do
  @moduledoc """
  Multiplayer Schulte tables. Each game is a `Octomocto.Schulte.Game`
  process, found by its id. Finished fields are saved as
  `Octomocto.Schulte.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.Repo
  alias Octomocto.Schulte.{Game, Result}

  @list_size 10

  @doc """
  Starts a new game with a `:random` or a `:classic` layout, in the
  `:easy` or the `:normal` mode, for the given number of players, and
  returns its id.
  """
  def create_game(layout, mode, players) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(
        Octomocto.Schulte.GameSupervisor,
        {Game, {id, layout, mode, players}}
      )

    id
  end

  def game_exists?(id) do
    Registry.lookup(Octomocto.Schulte.Registry, id) != []
  end

  @doc """
  Adds a player for the calling process. The player is removed when the
  process stops. Subscribe to `Game.topic(id)` first to get all updates.
  The `user_id` is nil for a guest. The `name` is the display name, or nil
  for a color name. When the game has all its players, the new process only
  watches, and the player id is nil.
  """
  def join(id, user_id \\ nil, name \\ nil) do
    if game_exists?(id) do
      GenServer.call(Game.via(id), {:join, self(), user_id, name})
    else
      {:error, :not_found}
    end
  end

  @doc "The player clicks a number. Only the next number counts."
  def pick(id, player_id, number) when is_integer(number) do
    GenServer.cast(Game.via(id), {:pick, player_id, number})
  end

  @doc "Starts a new field with zero scores, after all numbers are found."
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
  `%{"type" => "classic", "mode" => "easy", "players" => 2}`: the latest games (with all
  players, the best score first) and the best result of each signed-in
  user (the fastest first).
  """
  def leaderboard(settings) do
    %{latest: latest_games(settings), best: best_results(settings)}
  end

  @doc """
  Gives the results of the scope's user for the settings: the latest
  results (the newest first) and the best result (nil when there are no
  results).
  """
  def user_results(%{user: user}, settings) do
    user_query =
      from(r in Result, where: r.settings == type(^settings, :map) and r.user_id == ^user.id)

    latest =
      from(r in user_query, order_by: [desc: r.inserted_at], limit: @list_size)
      |> Repo.all()

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

    results =
      from(r in Result,
        where: r.game_id in ^game_ids,
        order_by: [desc: r.score],
        preload: :user
      )
      |> Repo.all()
      |> Enum.group_by(& &1.game_id)

    Enum.map(game_ids, fn game_id ->
      [first | _] = players = results[game_id]
      %{game_id: game_id, elapsed_ms: first.elapsed_ms, players: players}
    end)
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
