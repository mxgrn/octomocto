defmodule OctomoctoWeb.MatchPage do
  @moduledoc """
  The settings page of a match (`?match=<game id>`, see `Octomocto.Match`)
  for a game of `Octomocto.RaceServer` or `Octomocto.TurnServer`. The page
  shows the score of the match in place of the Players setting, and its
  Start button starts the next field of the same game with the new
  settings.

  A settings page uses it like this:

    * in `mount/3`, `load/4` gives the match (or nil), and `subscribe/3`
      gets the changes of its players,
    * the page puts the settings of the game into its params with
      `defaults/2`,
    * its `"new_game"` event calls `start/3`.
  """

  import Phoenix.LiveView, only: [connected?: 1, get_connect_params: 1]

  alias Octomocto.Match

  @doc """
  The match of the page, or nil: the `:id` of the game, the `:state` that
  its clients see, the `:player_id` of the player who changes the
  settings, and the `:settings` of the game (its state in the store,
  where the settings page finds the settings of the game, see
  `params/3`). The token of the player is in the connect params (see
  app.js), so the page holds the seat of the player only after the
  connect. Before the connect, the page only shows the score. The
  `channel` gives the player id of a token (`player_id/2`).
  """
  def load(id, socket, game, channel) when is_binary(id) do
    if connected?(socket) do
      token = get_connect_params(socket)["match_token"]

      with player_id when is_binary(player_id) <- channel.player_id(id, token),
           {:ok, state} <- Match.edit_settings(game, id, player_id),
           %{} = settings <- game.__game__().store.read(id) do
        %{id: id, player_id: player_id, state: state, settings: settings}
      else
        _ -> nil
      end
    else
      case game.__game__().store.read(id) do
        %{needed: needed} = state when needed > 1 ->
          %{id: id, player_id: nil, state: game.public(state), settings: state}

        _ ->
          nil
      end
    end
  end

  def load(_id, _socket, _game, _channel), do: nil

  @doc """
  Subscribes the connected page to the changes of the game of the match,
  as `{state_message, state}` messages. Else subscribes it to the lists
  of the settings page (see `Octomocto.Lobby`).
  """
  def subscribe(socket, match, game) do
    if connected?(socket) do
      if match,
        do: Phoenix.PubSub.subscribe(Octomocto.PubSub, game.topic(match.id)),
        else: Octomocto.Lobby.subscribe(game)
    end
  end

  @doc """
  The params of the page with the settings of the game of the match as
  the defaults (the link to the page has only the match), and with the
  number of players and the visibility of the game, which do not change.
  The `defaults` are the params of the other settings of the game.
  """
  def params(params, nil, _defaults), do: params

  def params(params, %{state: state}, defaults) do
    defaults
    |> Map.merge(params)
    |> Map.merge(%{
      "players" => Integer.to_string(state.players_needed),
      "visibility" => if(state.public, do: "public", else: "private")
    })
  end

  @doc """
  Starts the next field of the match with the `settings`. When they are
  not valid (or the game stopped), the game page shows the end screen
  again.
  """
  def start(game, %{id: id, player_id: player_id}, settings) do
    Match.change_settings(game, id, player_id, settings)
  end

  @doc """
  The path of the Change settings button of the game in the given state:
  the settings page at `path` with the match, or nil for a game with one
  player. The path has only the match, because the settings of the game
  can change after the page load.
  """
  def path(path, %{needed: needed, id: id}) when needed > 1, do: path <> "?match=" <> id
  def path(_path, _state), do: nil
end
