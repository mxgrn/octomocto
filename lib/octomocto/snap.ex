defmodule Octomocto.Snap do
  @moduledoc """
  Snap: a single-player game where the player says as fast as possible if
  each new card has the same shape as the card some places back (see
  `Octomocto.Snap.Game`). Each game is a `Octomocto.Snap.Game` process on
  one node of the cluster, found by its id. A copy of its state is in
  `Octomocto.Snap.Store`, so the game continues on another node when its
  node stops. Finished rounds are saved as `Octomocto.Snap.Result` rows.
  """

  import Ecto.Query

  alias Octomocto.GameProcess
  alias Octomocto.Repo
  alias Octomocto.Snap.{Game, Result, Store}

  @list_size 10

  @doc """
  Starts a new game and returns its id. The `config` has `:back`, the
  number of places back of the card to compare with (1 to 3).
  """
  def create_game(config) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    config = Map.merge(config, %{players: 1, public: false})

    {:ok, _pid} =
      DynamicSupervisor.start_child(Octomocto.Snap.GameSupervisor, {Game, {id, config}})

    id
  end

  def game_exists?(id) do
    Store.read(id) != nil
  end

  @doc """
  Adds the player for the calling process, see `Octomocto.Overlap.join/5`.
  A second browser only watches.
  """
  def join(id, user_id \\ nil, name \\ nil, player_id \\ nil, guest_id \\ nil) do
    GameProcess.join(
      Game,
      Store,
      Octomocto.Snap.GameSupervisor,
      id,
      user_id,
      name,
      player_id,
      guest_id
    )
  end

  @doc "Gives the state of the game to a process that only watches."
  def watch(id) do
    GameProcess.watch(Game, Store, Octomocto.Snap.GameSupervisor, id)
  end

  @doc """
  The player says if the card at `index` has the same shape (`same` is
  true) as the card `back` places before it. Only the next card counts.
  """
  def answer(id, player_id, index, same) do
    GenServer.cast(Game.via(id), {:answer, player_id, index, same})
  end

  @doc "The clock of the page is over: the round ends when it is over on the server too."
  def time_up(id, player_id) do
    GenServer.cast(Game.via(id), {:time_up, player_id})
  end

  @doc "Starts a new round with a zero score. Only the player can."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end

  @doc """
  Saves one finished round. The player is a map with `:user_id` (nil for a
  guest), `:name`, `:guest_id` (see `Octomocto.Guests`), `:score`,
  `:correct` and `:wrong`.
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
          correct: player.correct,
          wrong: player.wrong,
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
      from(r in user_query, order_by: [desc: r.score, asc: r.inserted_at], limit: 1)
      |> Repo.one()

    %{latest: latest, best: best}
  end

  @doc """
  Gives the best result of each signed-in user for the settings (the
  highest score first).
  """
  def best_results(settings) do
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
