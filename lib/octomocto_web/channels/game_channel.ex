defmodule OctomoctoWeb.GameChannel do
  @moduledoc """
  The join and the rejoin of a game channel, the same for all games with a
  `Octomocto.GameStore`. A channel calls `join/4` from its `join/3` and
  gives the messages that it does not handle itself to `handle_info/3`.

  Each join adds a new player (a guest when the socket has no user). The
  join reply has the player id, a token of the player, and the full game
  state. The player id and the token are nil when the game does not take
  more players: then the browser only watches.

  The browser sends the token in the join params when it joins again (for
  example, after a reload or a reconnect to another node in a deploy), and
  gets back the same player. A browser with `"watch": true` in the join
  params and no token of a player only watches, also when the game has a
  free seat. When the game stops on its node, the channel
  joins the game again (on this node) and pushes a new reply as a
  `"joined"` event.

  The `opts` are:

    * `:context` - the module with `join/4`, for example `Octomocto.Schulte`,
      and `watch/1` when its browsers can only watch,
    * `:game` - the game process module, with `via/1` and `topic/1`,
    * `:salt` - the salt of the player tokens of this game,
    * `:kind` - the id of the game in `OctomoctoWeb.HomeLive.games/0`.

  When a player starts the next game (see `OctomoctoWeb.NextGame`), the
  channels of the players push its id as a `"next_game"` event.
  """
  import Phoenix.Channel, only: [push: 3]
  import Phoenix.Socket, only: [assign: 2]

  alias Octomocto.Accounts

  # In seconds
  @token_max_age 24 * 60 * 60
  @rejoin_delay_ms 1000

  def join(game_id, params, socket, opts) do
    Phoenix.PubSub.subscribe(Octomocto.PubSub, opts[:game].topic(game_id))

    player_id = verify_token(game_id, params["token"], opts)

    socket =
      assign(socket, game_id: game_id, player_id: player_id, watch: params["watch"] == true)

    case join_game(socket, opts) do
      {:ok, reply, socket} -> {:ok, reply, socket}
      {:error, reason} -> {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  # The game ended because nobody played
  def handle_info(
        {:DOWN, ref, :process, _pid, :normal},
        %{assigns: %{game_ref: ref}} = socket,
        _opts
      ) do
    {:noreply, socket}
  end

  # The node of the game stopped
  def handle_info(
        {:DOWN, ref, :process, _pid, _reason},
        %{assigns: %{game_ref: ref}} = socket,
        _opts
      ) do
    send(self(), :rejoin)
    {:noreply, socket}
  end

  # A browser that only watches does not go to the next game
  def handle_info({:next_game, id}, socket, _opts) do
    if socket.assigns.player_id, do: push(socket, "next_game", %{id: id})
    {:noreply, socket}
  end

  def handle_info(:rejoin, socket, opts) do
    case join_game(socket, opts) do
      {:ok, reply, socket} ->
        push(socket, "joined", reply)
        {:noreply, socket}

      {:error, :unavailable} ->
        Process.send_after(self(), :rejoin, @rejoin_delay_ms)
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  defp join_game(socket, opts) do
    with {:ok, player_id, state} <- join_or_watch(socket.assigns, opts) do
      game_id = socket.assigns.game_id
      socket = assign(socket, player_id: player_id, game_ref: monitor_game(game_id, opts))
      reply = %{player_id: player_id, token: sign_token(game_id, player_id, opts), state: state}
      {:ok, reply, socket}
    end
  end

  defp join_or_watch(%{game_id: game_id, player_id: nil, watch: true}, opts) do
    opts[:context].watch(game_id)
  end

  defp join_or_watch(%{game_id: game_id, player_id: player_id} = assigns, opts) do
    user_id = assigns[:user_id]
    opts[:context].join(game_id, user_id, player_name(user_id, assigns[:guest_name]), player_id)
  end

  # A guest without a guest name is known by the color
  defp player_name(nil, guest_name), do: guest_name
  defp player_name(user_id, _guest_name), do: Accounts.display_name(user_id)

  defp monitor_game(game_id, opts) do
    case GenServer.whereis(opts[:game].via(game_id)) do
      # The game stopped a moment ago
      nil ->
        send(self(), :rejoin)
        nil

      pid ->
        Process.monitor(pid)
    end
  end

  defp sign_token(_game_id, nil, _opts), do: nil

  defp sign_token(game_id, player_id, opts) do
    Phoenix.Token.sign(OctomoctoWeb.Endpoint, opts[:salt], {game_id, player_id})
  end

  defp verify_token(game_id, token, opts) when is_binary(token) do
    case Phoenix.Token.verify(OctomoctoWeb.Endpoint, opts[:salt], token, max_age: @token_max_age) do
      {:ok, {^game_id, player_id}} -> player_id
      _ -> nil
    end
  end

  defp verify_token(_game_id, _token, _opts), do: nil
end
