defmodule Octomocto.Match do
  @moduledoc """
  The match of a game with 2 or more players (see `Octomocto.RaceServer`
  and `Octomocto.TurnServer`): the players play more fields in the same
  game, and each finished field gives a win to its winner (`wins` of the
  player), or a tie (`ties` of the game) when there is no single winner.

  Between two fields, one player can change the settings of the game on
  the settings page (see `edit_settings/4`). The player is in `editing`
  while the page is open, and the other players cannot start a field
  until the player is back. The page then starts the next field with the
  new settings (see `change_settings/4`).
  """

  @doc "Adds the fields of the match to the state of a new game."
  def new(state), do: Map.merge(state, %{editing: nil, ties: 0})

  @doc """
  Adds the fields of the match to a state from older code. The page of a
  player who changed the settings was on the old node, so nobody edits.
  """
  def restore(state), do: state |> Map.put_new(:ties, 0) |> Map.put(:editing, nil)

  @doc "Adds the fields of the match to a new player."
  def new_player(fields), do: Map.put(fields, :wins, 0)

  @doc "The wins of a player. A player from older code has no `:wins`."
  def wins(player), do: Map.get(player, :wins, 0)

  @doc "The ids of the players with the most points."
  def top_scorers(state) do
    top = state.players |> Map.values() |> Enum.map(& &1.score) |> Enum.max(fn -> 0 end)
    for {id, p} <- state.players, p.score == top, do: id
  end

  @doc """
  Counts a finished field of a game with 2 or more players: a win for the
  one winner, else a tie.
  """
  def count(state, winners) when state.needed > 1 do
    case winners do
      [id] when is_map_key(state.players, id) ->
        update_in(state.players[id], &Map.put(&1, :wins, wins(&1) + 1))

      _ ->
        Map.update(state, :ties, 1, &(&1 + 1))
    end
  end

  def count(state, _winners), do: state

  @doc """
  True when the player can go to the settings page: the game has 2 or
  more players, the field is finished, and no other player is there.
  """
  def edit?(state, player_id) do
    is_map_key(state.players, player_id) and state.needed > 1 and state.finished_at != nil and
      state.editing in [nil, player_id]
  end

  @doc """
  The player goes to the settings page. The calling process holds the seat
  of the player, and the other players wait until the player changes the
  settings (`change_settings/4`) or joins the game again. Gives
  `{:ok, state}` with the state that clients see, or `{:error, reason}`.
  """
  def edit_settings(game, id, player_id, pid \\ self()) do
    GenServer.call(game.via(id), {:edit_settings, pid, player_id})
  catch
    :exit, _reason -> {:error, :not_found}
  end

  @doc """
  Starts the next field with the new `settings` (see the
  `change_settings/2` callback of the server). Only the player of
  `edit_settings/4` can. Gives `:ok` or `{:error, reason}`.
  """
  def change_settings(game, id, player_id, settings) do
    GenServer.call(game.via(id), {:change_settings, player_id, settings})
  catch
    :exit, _reason -> {:error, :not_found}
  end
end
