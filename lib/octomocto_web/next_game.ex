defmodule OctomoctoWeb.NextGame do
  @moduledoc """
  The game that the end screen of a game invites the players to try ("Or
  try …"). All browsers of a game get the same next game, so that the
  players can go on together.

  In a game with 2 or more players, a player can start the next game for
  all players (`start/2`): the game process creates the next game in the
  default settings, for the number of players in the game and with the same
  visibility. The channels of the players push its id as a `"next_game"`
  event, and the browsers go to it. A browser that only watches stays.

  A game process gives the next game with a `{:next_game, player_id, page}`
  call, see `Octomocto.GameProcess.next_game/3`.
  """
  alias OctomoctoWeb.HomeLive

  @doc """
  The next game after a game of the `kind` (an id in `HomeLive.games/0`).
  After a `multiplayer` game, it is never a single-player game, because
  all players go to it together.
  """
  def pick(kind, game_id, multiplayer) do
    games =
      Enum.reject(HomeLive.games(), &(&1.id == kind or (multiplayer and &1[:single_player])))

    Enum.at(games, :erlang.phash2(game_id, length(games)))
  end

  @doc """
  Starts the next game for all players of the game of the channel socket.
  The `opts` are the opts of `OctomoctoWeb.GameChannel`.
  """
  def start(socket, opts) do
    %{game_id: game_id, player_id: player_id} = socket.assigns
    page = HomeLive.settings_page(pick(opts[:kind], game_id, true).id)

    if id = GenServer.call(opts[:game].via(game_id), {:next_game, player_id, page}) do
      Phoenix.PubSub.broadcast(Octomocto.PubSub, opts[:game].topic(game_id), {:next_game, id})
    end
  catch
    # The game stopped. The player can click again after the rejoin.
    :exit, _reason -> nil
  end
end
