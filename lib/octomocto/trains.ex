defmodule Octomocto.Trains do
  @moduledoc """
  Cooperative trains games. Each game is a `Octomocto.Trains.Game` process
  on one node of the cluster, found by its id. A copy of its state is in
  `Octomocto.Trains.Store`, so the game continues on another node when its
  node stops.
  """

  alias Octomocto.Trains.{Game, Store}

  @switch_counts [4, 6, 8, 12]
  @paces ~w(easy normal hard expert)

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
    * `:pace` - see `paces/0`.
  """
  def create_game(
        %{players: players, switch_count: switches, trains_per_house: trains, pace: pace} =
          settings
      )
      when players in 1..4 and switches in @switch_counts and rem(switches, players) == 0 and
             trains in 1..7 and pace in @paces do
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
    case game_pid(id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:join, self(), user_id, name, player_id})
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  # When no node runs the game (for example, its node stopped in a deploy),
  # starts the game on this node from its copy in the store.
  defp game_pid(id) do
    with nil <- GenServer.whereis(Game.via(id)),
         %{} = state <- Store.read(id) do
      case DynamicSupervisor.start_child(Octomocto.Trains.GameSupervisor, {Game, state}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end
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

  @doc "Starts a new round with a new board."
  def restart(id, player_id) do
    GenServer.cast(Game.via(id), {:restart, player_id})
  end
end
