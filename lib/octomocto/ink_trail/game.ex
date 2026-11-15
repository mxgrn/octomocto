defmodule Octomocto.InkTrail.Game do
  @moduledoc """
  One Ink Trail game for one player. A leader octopus jets between
  caves, one jet at a time, on a random path. The player's octopus
  follows the same path, some jets behind: the distance. The player only
  sees the two octopi, so the player must remember the path between them.

  At each tap, the player picks the next cave of the path of the
  player's octopus, and then the leader jets once more. Each correct tap
  gives points times the distance. Each 5 correct taps in a row make the
  distance one larger (up to 11): the leader jets once more. A wrong tap makes the
  distance one smaller (but not less than 3): the player's octopus goes to the
  correct cave, and the leader waits. The leader waits for each tap, so
  the game has no clock. The game ends after 40 correct taps.

  The game starts at the distance where the last game of the player ended
  (see `Octomocto.InkTrail.start_distance/2`), and a restart starts at the
  current distance, but never below 3.

  The path has the indexes of the caves, up to the cave of the leader. The
  leader is at the index `leader` of the path, and the player's octopus at
  the index `follower`. The leader picks each new cave when it jets (see
  `jet/1`): never its own cave, the cave of the player's octopus, or the cave
  where the player's octopus must jet next, so that the leader does not give
  the answer away. The page checks each tap itself for the score on the
  screen, and sends it here too. The taps here give the score that the game
  saves. The page shows the jets of the leader when the new path comes.

  The player, the clock and the copy in `Octomocto.InkTrail.Store` are
  the same as in the other games, see `Octomocto.RaceServer`. Each change
  is broadcast on the `"ink-trail:<id>"` PubSub topic as
  `{:ink_trail_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "ink-trail",
    state_message: :ink_trail_state,
    lobby_topic: "ink_trail_lobby",
    store: Octomocto.InkTrail.Store,
    context: Octomocto.InkTrail

  alias Octomocto.RaceServer

  @caves 12
  @goal 40
  @min_start 3
  @min_distance 3
  # The caves of the trail (the player's octopus, the leader and the caves
  # between them) are all different, and the leader needs a free cave for
  # its next jet: so 12 caves allow the distance 11 at most
  @max_distance 11
  @streak_step 5
  @points 10

  def caves, do: @caves

  @doc "The smallest distance at the start of a game."
  def min_start, do: @min_start

  @doc "The largest distance."
  def max_distance, do: @max_distance

  @impl true
  def init_settings(%{start_distance: distance}) when distance in @min_start..@max_distance,
    do: %{start_distance: distance}

  @impl true
  def new_player(player),
    do: Map.merge(player, %{correct: 0, wrong: 0, streak: 0, best_distance: 0, last_distance: 0})

  @impl true
  def reset_player(player),
    do: %{player | correct: 0, wrong: 0, streak: 0, best_distance: 0, last_distance: 0}

  # A restart starts at the current distance
  @impl true
  def new_field(state) do
    distance =
      case state do
        %{leader: leader, follower: follower} ->
          min(max(leader - follower, @min_start), @max_distance)

        _first ->
          state.start_distance
      end

    # The leader makes its first jets from the cave of the player's octopus.
    # The page shows the leader on its first cave at the start, one jet
    # ahead.
    state = Map.merge(state, %{path: [:rand.uniform(@caves) - 1], leader: 0, follower: 0})
    jet(state, distance)
  end

  defp jet(state, times), do: Enum.reduce(1..times//1, state, fn _i, state -> jet(state) end)

  # The leader jets to a random cave that is not on the trail: not the cave
  # of the player's octopus, not its own cave, and not a cave between them. Thus
  # the two octopi are never on one cave, and the leader never shows where the
  # player's octopus must go.
  defp jet(state) do
    taken = Enum.slice(state.path, state.follower..state.leader)
    cave = Enum.random(Enum.to_list(0..(@caves - 1)) -- taken)
    %{state | path: state.path ++ [cave], leader: state.leader + 1}
  end

  @impl true
  def handle_move({:tap, player_id, step, cave}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if RaceServer.started?(state) and step == state.follower + 1 do
      {:publish, :ok, tap(state, player_id, cave)}
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move(_move, state), do: {:ignore, :ok, state}

  defp tap(state, player_id, cave) do
    player = state.players[player_id]
    distance = state.leader - state.follower
    correct? = Enum.at(state.path, state.follower + 1) == cave

    {player, jets} =
      if correct? do
        streak = player.streak + 1
        grow? = rem(streak, @streak_step) == 0 and distance < @max_distance

        {%{
           player
           | score: player.score + @points * distance,
             correct: player.correct + 1,
             streak: if(grow?, do: 0, else: streak)
         }, if(grow?, do: 2, else: 1)}
      else
        # The leader waits, so the distance gets smaller, but not below 3
        {%{player | wrong: player.wrong + 1, streak: 0},
         if(distance > @min_distance, do: 0, else: 1)}
      end

    new_distance = distance - 1 + jets
    # The distance at the start counts too
    player = %{player | best_distance: Enum.max([player.best_distance, distance, new_distance])}

    # The player's octopus jets first, then the leader
    state =
      %{state | follower: state.follower + 1}
      |> put_in([:players, player_id], player)
      |> jet(jets)

    if player.correct == @goal do
      state
      |> put_in([:players, player_id, :last_distance], state.leader - state.follower)
      |> RaceServer.finish()
    else
      state
    end
  end

  @impl true
  def lobby_settings(_state), do: %{}

  @impl true
  def result_settings(_state), do: %{}

  @impl true
  def public_field(state) do
    player =
      Map.values(state.players)
      |> List.first(%{correct: 0, wrong: 0, streak: 0, best_distance: 0, last_distance: 0})

    %{
      # Tells a new game from the old one
      field: state.field_id,
      caves: @caves,
      # Nobody sees the path before the start
      path: if(RaceServer.started?(state), do: state.path, else: []),
      leader: state.leader,
      follower: state.follower,
      goal: @goal,
      points: @points,
      streak_step: @streak_step,
      max_distance: @max_distance,
      # So that the page can go on after a reload
      correct: player.correct,
      wrong: player.wrong,
      streak: player.streak,
      best_distance: player.best_distance,
      last_distance: player.last_distance
    }
  end
end
