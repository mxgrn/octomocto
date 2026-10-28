defmodule Octomocto.GameProcess do
  @moduledoc """
  Finds the process of a game in the cluster. A game process is registered
  with `game.via(id)` and keeps a copy of its state in a
  `Octomocto.GameStore`. When no node runs the game (for example, its node
  stopped in a deploy), the game starts again on this node from that copy,
  under the `supervisor`.

  A server of games (`Octomocto.RaceServer` or `Octomocto.TurnServer`)
  uses this module in its own `__using__`, so that each game module gets
  its name in the cluster, its topics, its child spec and its start:

      use Octomocto.GameProcess,
        server: Octomocto.RaceServer,
        # The options of `use Octomocto.RaceServer` in the game module
        options: [topic: "sudoku", state_message: :sudoku_state, ...]

  The server must have `start_link/2` and `lobby_entry/2`, both with the
  game module as the first argument. It reads the options with
  `game.__game__()`.
  """

  defmacro __using__(opts) do
    quote bind_quoted: [server: Keyword.fetch!(opts, :server), options: opts[:options]] do
      @game_server server
      @game_options Map.new(options)

      @doc """
      The child spec of the game for a supervisor. The game is
      `:temporary`: the supervisor does not start it again when it stops,
      because a stopped game starts again from its store on the next join
      (see `Octomocto.GameProcess`).
      """
      def child_spec(arg) do
        %{id: __MODULE__, start: {__MODULE__, :start_link, [arg]}, restart: :temporary}
      end

      @doc """
      Starts a new game from `{id, config}`, or again from its state in the
      store. See `#{inspect(server)}.start_link/2`.
      """
      def start_link(arg), do: @game_server.start_link(__MODULE__, arg)

      @doc """
      The name of the game `id` in the whole cluster, so that a process on
      any node finds the game.
      """
      def via(id), do: {:via, :global, {__MODULE__, id}}

      @doc """
      The PubSub topic of the game `id`. The game sends each change on it as
      `{state_message, state}`, with the `:state_message` of the `use`
      options.
      """
      def topic(id), do: @game_options.topic <> ":" <> id

      @doc """
      The PubSub topic where all games of this kind send their rows for the
      lists of the settings page (see `Octomocto.Lobby`).
      """
      def lobby_topic, do: @game_options.lobby_topic

      @doc "The row of the game in the lists, see `#{inspect(server)}.lobby_entry/2`."
      def lobby_entry(state), do: @game_server.lobby_entry(__MODULE__, state)

      # The options of `use`, for the functions of the server
      @doc false
      def __game__, do: @game_options
    end
  end

  @doc """
  Adds a player for the calling process with a `{:join, pid, user_id, name,
  player_id, guest_id}` call to the game, and gives the reply of the game.
  The `guest_id` is nil for a user (see `Octomocto.Guests`). Gives
  `{:error, :not_found}` when the game does not exist, and
  `{:error, :unavailable}` when the node of the game stopped a moment ago
  (try again soon).
  """
  def join(game, store, supervisor, id, user_id, name, player_id, guest_id) do
    call(game, store, supervisor, id, {:join, self(), user_id, name, player_id, guest_id})
  end

  @doc """
  Gives the reply of a `:watch` call to the game: the state for a process
  that only watches. Gives the same errors as `join/8`.
  """
  def watch(game, store, supervisor, id) do
    call(game, store, supervisor, id, :watch)
  end

  @doc """
  The reply of a game process to a `{:next_game, player_id, page}` call
  (see `OctomoctoWeb.NextGame`): the id of the next game and the new state.
  The first call creates the game with `page.create_default_game/2`, for
  the number of players and with the visibility of the game. The next
  calls give the same id. A restart must delete `:next_game` from the
  state. The id is nil for a player who is not in the game.
  """
  def next_game(state, player_id, page) when is_map_key(state.players, player_id) do
    state =
      Map.put_new_lazy(state, :next_game, fn ->
        page.create_default_game(map_size(state.players), state.public)
      end)

    {state.next_game, state}
  end

  def next_game(state, _player_id, _page), do: {nil, state}

  defp call(game, store, supervisor, id, request) do
    case whereis(game, store, supervisor, id) do
      nil -> {:error, :not_found}
      pid -> GenServer.call(pid, request)
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
