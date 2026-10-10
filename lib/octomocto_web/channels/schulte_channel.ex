defmodule OctomoctoWeb.SchulteChannel do
  @moduledoc """
  Connects one browser to a Schulte game. Each join adds a new player (a
  guest when the socket has no user). The join reply has the player id, a
  token of the player, and the full game state, and each later change is
  pushed as a `"state"` event. The player id and the token are nil when the
  game is full: then the browser only watches.

  The browser sends the token in the join params when it joins again (for
  example, after a reconnect to another node in a deploy), and gets back
  the same player. When the game stops on its node, the channel joins the
  game again (on this node) and pushes a new reply as a `"joined"` event.
  """
  use Phoenix.Channel

  alias Octomocto.Accounts
  alias Octomocto.Schulte
  alias Octomocto.Schulte.Game

  @token_salt "schulte player"
  # In seconds
  @token_max_age 24 * 60 * 60
  @rejoin_delay_ms 1000

  @impl true
  def join("schulte:" <> game_id, params, socket) do
    Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(game_id))

    socket = assign(socket, game_id: game_id, player_id: verify_token(game_id, params["token"]))

    case join_game(socket) do
      {:ok, reply, socket} -> {:ok, reply, socket}
      {:error, reason} -> {:error, %{reason: Atom.to_string(reason)}}
    end
  end

  @impl true
  def handle_in("pick", %{"number" => number}, socket) when is_integer(number) do
    Schulte.pick(socket.assigns.game_id, socket.assigns.player_id, number)
    {:noreply, socket}
  end

  def handle_in("restart", _params, socket) do
    Schulte.restart(socket.assigns.game_id)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:schulte_state, state}, socket) do
    push(socket, "state", state)
    {:noreply, socket}
  end

  # The game ended because nobody played
  def handle_info({:DOWN, ref, :process, _pid, :normal}, %{assigns: %{game_ref: ref}} = socket) do
    {:noreply, socket}
  end

  # The node of the game stopped
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{assigns: %{game_ref: ref}} = socket) do
    send(self(), :rejoin)
    {:noreply, socket}
  end

  def handle_info(:rejoin, socket) do
    case join_game(socket) do
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

  defp join_game(socket) do
    %{game_id: game_id, player_id: player_id} = socket.assigns
    user_id = socket.assigns[:user_id]

    with {:ok, player_id, state} <-
           Schulte.join(game_id, user_id, Accounts.display_name(user_id), player_id) do
      socket = assign(socket, player_id: player_id, game_ref: monitor_game(game_id))
      reply = %{player_id: player_id, token: sign_token(game_id, player_id), state: state}
      {:ok, reply, socket}
    end
  end

  defp monitor_game(game_id) do
    case GenServer.whereis(Game.via(game_id)) do
      # The game stopped a moment ago
      nil ->
        send(self(), :rejoin)
        nil

      pid ->
        Process.monitor(pid)
    end
  end

  defp sign_token(_game_id, nil), do: nil

  defp sign_token(game_id, player_id) do
    Phoenix.Token.sign(OctomoctoWeb.Endpoint, @token_salt, {game_id, player_id})
  end

  defp verify_token(game_id, token) when is_binary(token) do
    case Phoenix.Token.verify(OctomoctoWeb.Endpoint, @token_salt, token, max_age: @token_max_age) do
      {:ok, {^game_id, player_id}} -> player_id
      _ -> nil
    end
  end

  defp verify_token(_game_id, _token), do: nil
end
