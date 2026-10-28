defmodule Octomocto.Seats do
  @moduledoc """
  The players of a game process, the same for all games on
  `Octomocto.RaceServer` and `Octomocto.TurnServer`.

  The game is for a set number of players (`needed`). A process that joins
  a full game only watches. Each player is bound to the process that
  joined (a channel). When that process stops, the player stays in the
  game for a short time (`rejoin_grace_ms`), so that the same player can
  join again (for example, after a reconnect). Then the player is removed.
  The game stops after some time with no players.

  A public game is in the lists of the settings page (see
  `Octomocto.Lobby`): in the open games until it has all its players for
  the first time (`listed`), then in the ongoing games.

  The functions work on the flat state map of the game, and run in the
  game process: they monitor the processes of the players, and send
  messages to the game itself (`{:remove, player_id, ref}` and
  `:idle_check`).
  """
  alias Octomocto.Lobby

  @idle_timeout_ms :timer.minutes(5)
  @rejoin_grace_ms :timer.seconds(15)

  @colors [
    {"pink", "#ec4899"},
    {"sky", "#0ea5e9"},
    {"lime", "#65a30d"},
    {"amber", "#d97706"},
    {"violet", "#8b5cf6"},
    {"red", "#dc2626"},
    {"teal", "#0d9488"},
    {"indigo", "#4f46e5"}
  ]

  @doc """
  The fields of the seats in the state of a new game. The config has the
  number of `:players`, `:public`, and optionally `:rejoin_grace_ms`.
  """
  def new(id, %{players: needed, public: public} = config) do
    %{
      id: id,
      needed: needed,
      players: %{},
      public: public,
      created_at: now(),
      # True while the game is in the list of open games. A game with one
      # player is never in it.
      listed: public and needed > 1,
      rejoin_grace_ms: Map.get(config, :rejoin_grace_ms, @rejoin_grace_ms)
    }
  end

  @doc "Adds the fields of the seats that a state from older code does not have."
  def restore(state) do
    state
    # A state from before the lists of the settings page
    |> Map.put_new(:public, false)
    |> Map.put_new(:created_at, now())
    |> Map.put_new(:listed, false)
    # A state from before the timings in the config
    |> Map.put_new(:rejoin_grace_ms, @rejoin_grace_ms)
  end

  @doc "True when the game has all its players."
  def full?(state), do: map_size(state.players) >= state.needed

  @doc "Binds a player of the game to the process `pid` again."
  def rejoin(state, player_id, pid) do
    Process.monitor(pid)
    update_in(state.players[player_id], &%{&1 | pid: pid, left: nil})
  end

  @doc """
  Adds a new player for the process `pid`, with a color that no other
  player has, if possible. The `fields` are the fields of the game, such
  as `:score`. Gives the id of the player and the new state.
  """
  def add(state, pid, user_id, name, guest_id, fields) do
    Process.monitor(pid)
    # Unique in the cluster, because the game can move to another node
    player_id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    {color_name, color} = pick_color(state.players)

    player =
      Map.merge(fields, %{
        pid: pid,
        user_id: user_id,
        guest_id: guest_id,
        name: name,
        color: color,
        color_name: color_name,
        joined_at: System.system_time(),
        # A reference while the player is away, see leave/2
        left: nil
      })

    {player_id, put_in(state.players[player_id], player)}
  end

  @doc "The id of the player of the process `pid`, or nil."
  def player_id(state, pid) do
    Enum.find_value(state.players, fn {id, p} -> p.pid == pid and id end)
  end

  @doc "The player is away. It is removed after the grace time, unless it joins again."
  def leave(state, player_id) do
    left = make_ref()
    Process.send_after(self(), {:remove, player_id, left}, state.rejoin_grace_ms)
    update_in(state.players[player_id], &%{&1 | pid: nil, left: left})
  end

  @doc "All players are away, for a game that starts again on a new node."
  def leave_all(state), do: Enum.reduce(Map.keys(state.players), state, &leave(&2, &1))

  @doc """
  True when the `{:remove, player_id, left}` message is for a player that
  is still away since then, so that the game removes it now.
  """
  def remove?(state, player_id, left), do: match?(%{^player_id => %{left: ^left}}, state.players)

  @doc "Removes the player."
  def remove(state, player_id), do: %{state | players: Map.delete(state.players, player_id)}

  def schedule_idle_check, do: Process.send_after(self(), :idle_check, @idle_timeout_ms)

  @doc "The ids of the players, in the order in which they joined."
  def order(state) do
    state.players |> Enum.sort_by(fn {_id, p} -> p.joined_at end) |> Enum.map(&elem(&1, 0))
  end

  @doc """
  The players that clients see, in the order in which they joined. The
  `fields` function gives the fields of the game for a player id and a
  player.
  """
  def public_players(state, fields) do
    for id <- order(state) do
      p = state.players[id]

      Map.merge(
        %{id: id, name: p.name, color: p.color, color_name: p.color_name, away: p.left != nil},
        fields.(id, p)
      )
    end
  end

  @doc """
  The row of the game in the lists of the settings page (see
  `Octomocto.Lobby`), or nil when the game is in no list. The game is
  ongoing from `started_at` (nil before the start). The `fields` function
  gives the fields of the game for a player id and a player, such as
  `:score`.
  """
  # A state from before the lists has no `:public`
  def lobby_entry(%{public: true} = state, settings, started_at, fields)
      when map_size(state.players) > 0 do
    players =
      for id <- order(state),
          do: Map.merge(Lobby.player(state.players[id]), fields.(id, state.players[id]))

    entry = %{
      id: state.id,
      settings: settings,
      players_needed: state.needed,
      players: players,
      created_at: state.created_at
    }

    cond do
      state.listed ->
        Map.merge(entry, %{status: :open, seats_left: state.needed - map_size(state.players)})

      started_at != nil ->
        Map.merge(entry, %{
          status: :ongoing,
          started_at: started_at,
          finished: state.finished_at != nil
        })

      # Not all players are back after a restart
      true ->
        nil
    end
  end

  def lobby_entry(_state, _settings, _started_at, _fields), do: nil

  @doc """
  Writes the state to the `store` of the game, and sends the new row of
  the game to the settings pages.
  """
  def write(state, game, store) do
    store.write(state)
    if state.public, do: Lobby.broadcast(game, state.id, game.lobby_entry(state))
  end

  @doc "The system time in milliseconds, the same on all nodes."
  def now, do: System.system_time(:millisecond)

  # Prefer a color that no player has. Reuse colors when all are taken.
  defp pick_color(players) do
    taken = players |> Map.values() |> Enum.map(& &1.color)

    case Enum.reject(@colors, fn {_name, color} -> color in taken end) do
      [] -> Enum.random(@colors)
      free -> Enum.random(free)
    end
  end
end
