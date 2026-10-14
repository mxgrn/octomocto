defmodule Octomocto.Lobby do
  @moduledoc """
  The lists of public games on the settings page of each kind of game: the
  open games that wait for players, and the ongoing games that have
  started.

  A game module gives the row of a game in the lists with `lobby_entry/1`,
  or nil when the game is in no list. Only a public game can be in a list.
  After each change, such a game sends its new row with `broadcast/3`, and
  a settings page updates its rows with `put_entry/3`. The row is in the
  message, because the copy of the store on the node of a page can be older
  than the message.

  A row is a map with:

    * `:id` - the id of the game,
    * `:status` - `:open` or `:ongoing`,
    * `:settings` - the settings of the game, different for each kind of
      game,
    * `:players_needed` - the number of players of the game,
    * `:players` - the players in the order of the game, see `player/1`,
    * `:seats_left` and `:created_at` - for an open game,
    * `:started_at` and `:finished` - for an ongoing game. The
      `:started_at` is the start of the current field (or round).
  """

  @ongoing_size 10

  def topic(game), do: game.lobby_topic()

  def subscribe(game), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, topic(game))

  @doc "Sends the new row of a game. The `entry` is nil when the game is in no list."
  def broadcast(game, id, entry) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(game), {:lobby_changed, id, entry})
  end

  @doc """
  The row of a player. The `:name` is nil for a guest, and `:away` is true
  during the grace time. A game can add more, such as `:score` and
  `:turn` (true for the player of the turn).
  """
  def player(player) do
    %{name: player.name, color_name: player.color_name, away: player.left != nil}
  end

  @doc "The rows of all games of the `game` module in its `store`."
  def entries(game, store) do
    store.all()
    # The game of a node that stopped is in the store until a player joins
    # it again. Nobody plays in it.
    |> Enum.filter(&GenServer.whereis(game.via(&1.id)))
    |> Enum.map(&game.lobby_entry/1)
    |> Enum.reject(&is_nil/1)
  end

  @doc "Puts the new row of one game in the rows. The `entry` is nil when the game is in no list."
  def put_entry(entries, id, entry) do
    entries |> Enum.reject(&(&1.id == id)) |> Enum.concat(List.wrap(entry))
  end

  @doc """
  The games that wait for players, with the fewest free seats first, and
  the oldest game first when the free seats are the same.
  """
  def open_games(entries) do
    entries
    |> Enum.filter(&(&1.status == :open))
    |> Enum.sort_by(&{&1.seats_left, &1.created_at})
  end

  @doc """
  The #{@ongoing_size} games with the newest fields that have started, also
  the finished ones that the players did not start again.
  """
  def ongoing_games(entries) do
    entries
    |> Enum.filter(&(&1.status == :ongoing))
    |> Enum.sort_by(& &1.started_at, :desc)
    |> Enum.take(@ongoing_size)
  end
end
