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
  gets back the same player. When the game stops on its node, the channel
  joins the game again (on this node) and pushes a new reply as a
  `"joined"` event.

  The `opts` are:

    * `:context` - the module with `join/4`, for example `Octomocto.Schulte`,
    * `:game` - the game process module, with `via/1` and `topic/1`,
    * `:salt` - the salt of the player tokens of this game.
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
    socket = assign(socket, game_id: game_id, player_id: player_id)

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
    %{game_id: game_id, player_id: player_id} = socket.assigns
    user_id = socket.assigns[:user_id]

    with {:ok, player_id, state} <-
           opts[:context].join(game_id, user_id, Accounts.display_name(user_id), player_id) do
      socket = assign(socket, player_id: player_id, game_ref: monitor_game(game_id, opts))
      reply = %{player_id: player_id, token: sign_token(game_id, player_id, opts), state: state}
      {:ok, reply, socket}
    end
  end

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
