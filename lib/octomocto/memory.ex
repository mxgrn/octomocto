defmodule Octomocto.Memory do
  @moduledoc """
  Multiplayer memory game: find the matching pairs (or triplets) of cards.
  Each game is a `Octomocto.Memory.Game` process on one node of the cluster,
  found by its id. A copy of its state is in `Octomocto.Memory.Store`, so
  the game continues on another node when its node stops. Finished fields
  are saved as `Octomocto.Memory.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Repo
  alias Octomocto.Memory.{Game, Result, Store}

  @list_size 10

  @doc """
  Starts a new game and returns its id. The `config` has the `:theme`, the
  `:set` size (2 or 3), the number of `:cards`, the number of `:players`
  and `:public` (a public game is in `open_games/0`).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.Memory.GameSupervisor, {Game, {id, config}})

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
  caller can trust (see `OctomoctoWeb.MemoryChannel`).

  Gives `{:error, :unavailable}` when the node of the game stopped a
  moment ago. Try again soon.
  """
  def join(id, user_id \\ nil, name \\ nil, player_id \\ nil) do
    GameProcess.join(Game, Store, Octomocto.Memory.GameSupervisor, id, user_id, name, player_id)
  end

  @doc """
  Gives the state of the game to a process that only watches, also when the
  game has a free seat. Subscribe to `Game.topic(id)` first to get all
  updates. Gives the same errors as `join/4`.
  """
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.Memory.GameSupervisor, id)
  end

  @doc "The player turns a card face up. Only the player of the turn can."
  def flip(id, player_id, card_id) when is_integer(card_id) do
    GenServer.cast(Game.via(id), {:flip, player_id, card_id})
  end

  @doc "Starts a new field with the same settings and zero scores. Only a player can."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  Saves one finished field with its theme. Each player is a map with
  `:user_id` (nil for a guest), `:score`, `:correct` and `:errors`.
  """
  def save_results(game_id, settings, theme, elapsed_ms, players) do
    now = DateTime.utc_now()

    rows =
      Enum.map(players, fn player ->
        %{
          game_id: game_id,
          settings: settings,
          theme: theme,
          elapsed_ms: elapsed_ms,
          user_id: player.user_id,
          score: player.score,
          correct: player.correct,
          errors: player.errors,
          inserted_at: now
        }
      end)

    Repo.insert_all(Result, rows)
  end

  @doc """
  Gives the accuracy of a player (or a saved result) in percent, from its
  `:correct` and `:errors` flips. Only the flips where the player can know
  the answer are counted (see `Octomocto.Memory.Game`). Gives nil when no
  flip was counted, and for a result from before the accuracy.
  """
  def accuracy(%{correct: correct, errors: errors})
      when is_integer(correct) and is_integer(errors) and correct + errors > 0,
      do: round(100 * correct / (correct + errors))

  def accuracy(_player), do: nil

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
      from(r in without_guests(user_query),
        order_by: [asc: r.elapsed_ms, asc: r.inserted_at],
        limit: 1
      )
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
      from(r in without_guests(Result),
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
