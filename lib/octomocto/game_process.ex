defmodule Octomocto.GameProcess do
  @moduledoc """
  Finds the process of a game in the cluster. A game process is registered
  with `game.via(id)` and keeps a copy of its state in a
  `Octomocto.GameStore`. When no node runs the game (for example, its node
  stopped in a deploy), the game starts again on this node from that copy,
  under the `supervisor`.
  """

  @doc """
  Adds a player for the calling process with a `{:join, pid, user_id, name,
  player_id}` call to the game, and gives the reply of the game. Gives
  `{:error, :not_found}` when the game does not exist, and
  `{:error, :unavailable}` when the node of the game stopped a moment ago
  (try again soon).
  """
  def join(game, store, supervisor, id, user_id, name, player_id) do
    case whereis(game, store, supervisor, id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, {:join, self(), user_id, name, player_id})
    end
  catch
    :exit, _reason -> {:error, :unavailable}
  end

  defp whereis(game, store, supervisor, id) do
    with nil <- GenServer.whereis(game.via(id)),
         %{} = state <- store.read(id) do
      case DynamicSupervisor.start_child(supervisor, {game, state}) do
        {:ok, pid} -> pid
        {:error, {:already_started, pid}} -> pid
      end
    end
  end
end
