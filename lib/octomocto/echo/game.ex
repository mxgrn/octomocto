defmodule Octomocto.Echo.Game do
  @moduledoc """
  One Echo game: a ring of colored pads and a sequence of pads that gets
  one pad longer in each round.

  Alone, the player starts the game, and the game adds a random pad to the
  sequence. The browser plays the sequence back, and the player repeats it.
  When the player repeats all of it, the game adds one more random pad. A
  wrong pad ends the game.

  With 2 to 4 players, the game has no playback. In a turn, the player
  repeats the sequence and then adds a pad of their choice. Then the turn
  goes to the next player. The first player of a game only adds a pad. A
  player who taps a wrong pad is out. When only one player is still in,
  that player wins. A player who does nothing for some time loses the turn,
  but stays in. Nobody can tap a pad before the game has all its players.

  The score of a player is the length of the longest sequence that the
  player repeated. Each tap is in the state as the `last_tap`, so that the
  browsers of the other players light up its pad. When the game ends with
  all its players, it saves the score of each player (see
  `Octomocto.Echo.save_results/3`).

  The players, the turns, the lists of the settings page and the copy in
  `Octomocto.Echo.Store` are the same as in the other games with turns, see
  `Octomocto.TurnServer`. Each change is broadcast on the
  `"echo_game:<id>"` PubSub topic as `{:echo_state, state}`.
  """
  use Octomocto.TurnServer,
    topic: "echo_game",
    state_message: :echo_state,
    lobby_topic: "echo_lobby",
    store: Octomocto.Echo.Store

  alias Octomocto.{Echo, TurnServer}

  @impl true
  def init_settings(%{pads: pads}) when pads in 2..8 do
    # Counts the taps, so that a browser knows a new tap
    %{pads: pads, taps: 0}
  end

  @impl true
  def new_field(state) do
    Map.merge(state, %{
      # The pads, from 0
      sequence: [],
      # The number of pads of the sequence that the player of the turn
      # repeated. When it is the length of the sequence, the player adds a
      # pad (with 2 or more players).
      step: 0,
      # The id of the last player who is in, with 2 or more players
      winner: nil,
      # The last pad that a player tapped, see public_field/1
      last_tap: nil
    })
  end

  # The place in the order in which the players went out, or nil while the
  # player is in
  @impl true
  def new_player(player), do: Map.put(player, :out, nil)

  @impl true
  def reset_player(player), do: %{player | out: nil}

  @impl true
  def handle_move({:start, player_id}, %{turn: player_id, sequence: []} = state)
      when state.needed == 1 and state.ready and state.finished_at == nil do
    {:publish, :ok, add_random_pad(state)}
  end

  def handle_move({:start, _player_id}, state), do: {:ignore, :ok, state}

  # Alone, the player can tap only after the start
  def handle_move({:press, _player_id, _pad}, %{needed: 1, sequence: []} = state),
    do: {:ignore, :ok, state}

  def handle_move({:press, player_id, pad}, %{turn: player_id} = state)
      when is_binary(player_id) and pad in 0..(state.pads - 1)//1 and state.ready and
             state.finished_at == nil do
    state =
      if state.step < length(state.sequence),
        do: repeat(state, pad),
        else: add_pad(state, pad)

    {:publish, :ok, state}
  end

  def handle_move({:press, _player_id, _pad}, state), do: {:ignore, :ok, state}

  # Gives the turn to the next player who is in. The player starts the
  # sequence again from its first pad.
  @impl true
  def pass_turn(state) do
    %{state | step: 0, turn: next_player(state)}
  end

  # When only one player is still in, the game ends
  @impl true
  def after_remove(state), do: maybe_finish(state)

  # Alone, the first round starts at once
  @impl true
  def after_restart(state) do
    if state.needed == 1, do: add_random_pad(state), else: state
  end

  # The player of the turn taps the next pad of the sequence. After the last
  # pad, the player gets the length of the sequence as the score. Alone,
  # the game then adds a pad.
  defp repeat(state, pad) do
    if Enum.at(state.sequence, state.step) == pad do
      state = %{state | step: state.step + 1} |> tap(pad, true)
      length = length(state.sequence)

      cond do
        state.step < length ->
          TurnServer.restart_turn_timer(state)

        state.needed == 1 ->
          state |> put_score(length) |> add_random_pad()

        true ->
          state |> put_score(length) |> TurnServer.restart_turn_timer()
      end
    else
      state |> tap(pad, false) |> put_out() |> maybe_finish()
    end
  end

  # The player of the turn adds a pad, and the turn goes to the next player
  defp add_pad(state, pad) do
    %{state | sequence: state.sequence ++ [pad]}
    |> tap(pad, true)
    |> pass_turn()
    |> TurnServer.restart_turn_timer()
  end

  defp add_random_pad(state) do
    %{state | sequence: state.sequence ++ [Enum.random(0..(state.pads - 1))], step: 0}
  end

  defp tap(state, pad, ok) do
    taps = state.taps + 1
    %{state | taps: taps, last_tap: %{n: taps, pad: pad, player: state.turn, ok: ok}}
  end

  defp put_score(state, score) do
    update_in(state.players[state.turn].score, &max(&1, score))
  end

  # The player of the turn is out. Alone, the game ends. Else, the turn goes
  # to the next player who is in.
  defp put_out(state) do
    place = Enum.count(state.players, fn {_id, p} -> p.out != nil end) + 1
    state = put_in(state.players[state.turn].out, place)

    if state.needed == 1,
      do: state,
      else: state |> pass_turn() |> TurnServer.restart_turn_timer()
  end

  # The game ends when nobody (alone) or only one player (with 2 or more)
  # is still in
  defp maybe_finish(state) when state.ready and state.finished_at == nil do
    left = Enum.reject(state.players, fn {_id, p} -> p.out != nil end)

    if length(left) < min(state.needed, 2) do
      winner = if state.needed > 1, do: Enum.map(left, &elem(&1, 0)) |> List.first()
      turn = if state.needed > 1, do: winner, else: state.turn

      %{state | finished_at: TurnServer.now(), winner: winner, turn: turn}
      |> TurnServer.restart_turn_timer()
      |> save_results()
    else
      state
    end
  end

  defp maybe_finish(state), do: state

  # The players have their turns in the order in which they joined
  defp next_player(state) do
    order = Octomocto.Seats.order(state)
    {before, rest} = Enum.split_while(order, &(&1 != state.turn))

    # The players after the current one, then the ones before it, then the
    # current one
    (Enum.drop(rest, 1) ++ before ++ Enum.take(rest, 1))
    |> Enum.find(&(state.players[&1].out == nil))
  end

  defp save_results(state) when map_size(state.players) == state.needed do
    settings = %{"pads" => state.pads, "players" => state.needed}
    Echo.save_results(state.field_id, settings, Map.values(state.players))
    state
  end

  defp save_results(state), do: state

  @impl true
  def lobby_settings(state), do: %{pads: state.pads}

  @impl true
  def public_player(player), do: %{out: player.out}

  # With 2 or more players, the sequence is not in the public state: the
  # players must remember it. Alone, the browser plays it back.
  @impl true
  def public_field(state) do
    %{
      pads: state.pads,
      sequence: if(state.needed == 1, do: state.sequence),
      length: length(state.sequence),
      step: state.step,
      winner: state.winner,
      last_tap: state.last_tap
    }
  end
end
