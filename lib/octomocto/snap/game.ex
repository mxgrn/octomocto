defmodule Octomocto.Snap.Game do
  @moduledoc """
  One Snap game for one player. The cards come one by one, each with one
  shape. For each card, the player says if its shape is the same as the
  shape of the card `back` places before it. The first `back` cards are
  only to remember: each shows for a short time, and then the clock of the
  round runs for 45 seconds.

  A correct answer gives points times the multiplier. Each 4 correct
  answers in a row make the multiplier one larger, up to x5. A wrong answer
  sets it back to x1.

  The page has all cards of the round, so that the next card shows at once.
  It checks each answer itself, and sends it here too. The answers here
  give the score that the game saves. The page says when its clock is over,
  and the round ends when the clock here is over too.

  The player, the clock and the copy in `Octomocto.Snap.Store` are the same
  as in the other games, see `Octomocto.RaceServer`. Each change is
  broadcast on the `"snap:<id>"` PubSub topic as `{:snap_state, state}`.
  The answers only change the copy, because the page knows them already.
  """
  use Octomocto.RaceServer,
    topic: "snap",
    state_message: :snap_state,
    lobby_topic: "snap_lobby",
    store: Octomocto.Snap.Store,
    context: Octomocto.Snap

  alias Octomocto.RaceServer

  @shapes 8
  # More cards than the fastest player can answer in a round
  @cards 300
  # How long each card to remember shows
  @preview_ms 1500
  @play_ms 45_000
  # An answer that the page sent just before its clock was over can come a
  # bit later
  @late_ms 1000
  @points 50
  @streak_step 4
  @max_multiplier 5

  @impl true
  def init_settings(%{back: back}) when back in 1..3, do: %{back: back}

  @impl true
  def new_player(player), do: Map.merge(player, %{correct: 0, wrong: 0, streak: 0})

  @impl true
  def reset_player(player), do: %{player | correct: 0, wrong: 0, streak: 0}

  @impl true
  def new_field(state), do: Map.put(state, :cards, deal(state.back))

  # Half of the cards have the same shape as the card `back` places before
  # them, and the others have another shape.
  defp deal(back) do
    first = for _ <- 1..back, do: :rand.uniform(@shapes) - 1

    Enum.reduce((back + 1)..@cards//1, Enum.reverse(first), fn _i, cards ->
      earlier = Enum.at(cards, back - 1)

      shape =
        if :rand.uniform(2) == 1,
          do: earlier,
          else: Enum.random(Enum.to_list(0..(@shapes - 1)) -- [earlier])

      [shape | cards]
    end)
    |> Enum.reverse()
  end

  @impl true
  def handle_move({:answer, player_id, index, same}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    player = state.players[player_id]
    now = RaceServer.now()

    if RaceServer.started?(state) and now >= play_start(state) and
         now <= play_end(state) + @late_ms and index == state.back + answered(player) and
         index < @cards do
      same? = Enum.at(state.cards, index) == Enum.at(state.cards, index - state.back)
      player = if same? == same, do: correct(player), else: wrong(player)
      {:store, :ok, put_in(state.players[player_id], player)}
    else
      {:ignore, :ok, state}
    end
  end

  # The clock of the page is a bit late, so the clock here is over when the
  # page says so. A page that is too early says it again.
  def handle_move({:time_up, player_id}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if RaceServer.started?(state) and RaceServer.now() >= play_end(state) - @late_ms do
      {:publish, :ok, RaceServer.finish(state)}
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move(_move, state), do: {:ignore, :ok, state}

  defp correct(player) do
    multiplier = min(@max_multiplier, 1 + div(player.streak, @streak_step))

    %{
      player
      | score: player.score + @points * multiplier,
        correct: player.correct + 1,
        streak: player.streak + 1
    }
  end

  defp wrong(player), do: %{player | wrong: player.wrong + 1, streak: 0}

  defp answered(player), do: player.correct + player.wrong

  defp play_start(state), do: state.started_at + state.back * @preview_ms

  defp play_end(state), do: play_start(state) + @play_ms

  @impl true
  def lobby_settings(state), do: %{back: state.back}

  @impl true
  def result_settings(state), do: %{"back" => state.back}

  @impl true
  def public_field(state) do
    player =
      Map.values(state.players)
      |> List.first(%{correct: 0, wrong: 0, streak: 0})

    %{
      # Tells a new round from the old one
      field: state.field_id,
      back: state.back,
      # Nobody sees the cards before the start
      cards: if(RaceServer.started?(state), do: state.cards, else: []),
      preview_ms: @preview_ms,
      play_ms: @play_ms,
      points: @points,
      streak_step: @streak_step,
      max_multiplier: @max_multiplier,
      # So that the page can go on after a reload
      correct: player.correct,
      wrong: player.wrong,
      streak: player.streak
    }
  end
end
