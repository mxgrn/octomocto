defmodule Octomocto.Trains do
  @moduledoc """
  Cooperative trains games. Each game is a `Octomocto.Trains.Game` process
  on one node of the cluster, found by its id. A copy of its state is in
  `Octomocto.Trains.Store`, so the game continues on another node when its
  node stops. Finished rounds are saved as `Octomocto.Trains.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Repo
  alias Octomocto.Trains.{Game, Result, Store}

  @switch_counts [4, 6, 8, 12]
  @paces ~w(easy normal hard expert)
  @list_size 10

  @doc """
  How the pause between trains changes: it stays at 8 s (`"easy"`), or it
  goes from 8 s down to 2 s evenly (`"normal"`), along a square curve
  (`"hard"`) or along an exponential curve (`"expert"`). The harder curves
  get short sooner.
  """
  def paces, do: @paces

  @doc """
  The numbers of switches that divide equally between the players, so
  that each player owns the same number of switches.
  """
  def switch_counts(players) do
    Enum.filter(@switch_counts, &(rem(&1, players) == 0))
  end

  @doc """
  Gives the number of switches when it divides equally between the
  players. Otherwise gives the nearest number that does (the smaller one
  when two are equally near).
  """
  def fit_switch_count(switch_count, players) do
    Enum.min_by(switch_counts(players), &{abs(&1 - switch_count), &1})
  end

  @doc """
  Starts a new game and returns its id. The settings are:

    * `:players` - from 1 to 4,
    * `:switch_count` - see `switch_counts/1`,
    * `:trains_per_house` - from 1 to 7,
    * `:pace` - see `paces/0`,
    * `:public` - true when the game is in the lists of the settings page.
  """
  def create_game(
        %{
          players: players,
          switch_count: switches,
          trains_per_house: trains,
          pace: pace,
          public: public
        } = settings
      )
      when players in 1..4 and switches in @switch_counts and rem(switches, players) == 0 and
             trains in 1..7 and pace in @paces and is_boolean(public) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.Trains.GameSupervisor, {Game, {id, settings}})

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  Adds a player for the calling process. The player is removed some time
  after the process stops. Subscribe to `Game.topic(id)` first to get all
  updates. The `user_id` is nil for a guest. The `name` is the display
  name, or nil for a color name. When the game has all its players or
  started, the new process only watches, and the player id is nil.

  Give the `player_id` of a player that is still in the game to bind that
  player to the calling process again. Only give a player id that the
  caller can trust (see `OctomoctoWeb.TrainsChannel`).

  Gives `{:error, :unavailable}` when the node of the game stopped a
  moment ago. Try again soon.
  """
  def join(id, user_id \\ nil, name \\ nil, player_id \\ nil) do
    GameProcess.join(Game, Store, Octomocto.Trains.GameSupervisor, id, user_id, name, player_id)
  end

  @doc """
  Gives the state of the game to a process that only watches, also when the
  game has a free seat. Subscribe to `Game.topic(id)` first to get all
  updates. Gives the same errors as `join/4`.
  """
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.Trains.GameSupervisor, id)
  end

  @doc "Starts the round after a countdown, when the game has all its players."
  def start(id, player_id) do
    GenServer.cast(Game.via(id), {:start, player_id})
  end

  @doc "The player sets a switch at `cell` (`[x, y]`) to the position `value` (0 or 1)."
  def flip(id, player_id, cell, value) do
    GenServer.cast(Game.via(id), {:flip, player_id, cell, value})
  end

  @doc """
  The owner of the switch at `cell` sends the `train` (its number in the
  order of departure) to the `exit` cell. Only the first decision for a
  train at a switch counts.
  """
  def decide(id, player_id, train, cell, exit) do
    GenServer.cast(Game.via(id), {:decision, player_id, train, cell, exit})
  end

  @doc """
  The player tells that the round with the `seed` ended, and that
  `correct` trains got to the correct house. The server does not run the
  trains, so it trusts this number. Only the first report of a round
  counts.
  """
  def finish(id, player_id, seed, correct) do
    GenServer.cast(Game.via(id), {:finish, player_id, seed, correct})
  end

  @doc "Starts a new round with a new board."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  Saves one finished round. All players get the same `score`. Each player
  is a map with `:user_id` (nil for a guest).
  """
  def save_results(game_id, settings, score, players) do
    now = DateTime.utc_now()

    rows =
      Enum.map(players, fn player ->
        %{
          game_id: game_id,
          settings: settings,
          score: score,
          user_id: player.user_id,
          inserted_at: now
        }
      end)

    Repo.insert_all(Result, rows)
  end

  @doc """
  Gives the leaderboard for the settings, for example
  `%{"switch_count" => 6, "trains_per_house" => 2, "pace" => "normal",
  "players" => 2}`: the latest rounds (with all players) and the best
  result of each signed-in user (the most trains first).
  """
  def leaderboard(settings) do
    %{latest: latest_games(settings), best: best_results(settings)}
  end

  @doc """
  Gives the results of the scope's user for the settings: the latest
  results (the newest first, each with all players of its round, the user
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
      %{game_id: game_id, score: first.score, players: players[game_id]}
    end)
  end

  # Gives the results of all players of the rounds, by game id
  defp game_players(game_ids) do
    from(r in Result, where: r.game_id in ^game_ids, order_by: r.id, preload: :user)
    |> Repo.all()
    |> Enum.group_by(& &1.game_id)
  end

  defp best_results(settings) do
    best_of_each_user =
      from(r in Result,
        where: r.settings == type(^settings, :map) and not is_nil(r.user_id),
        distinct: r.user_id,
        order_by: [asc: r.user_id, desc: r.score, asc: r.inserted_at]
      )

    from(r in subquery(best_of_each_user),
      order_by: [desc: r.score, asc: r.inserted_at],
      limit: @list_size,
      preload: :user
    )
    |> Repo.all()
  end
end
