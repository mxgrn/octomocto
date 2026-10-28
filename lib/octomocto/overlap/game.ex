defmodule Octomocto.Overlap.Game do
  @moduledoc """
  One multiplayer Overlap game. The table has two cards: the top card of
  the pile and the next card from the deck (see `Octomocto.Overlap.Deck`).
  All players look for the symbol that the two cards have in common at the
  same time. The first player who taps it wins the card and gets one
  point. The card then goes on the pile, and the next card comes from the
  deck. Nobody sees the cards before the countdown is over. The deck is
  finished when it is empty.

  A tap on another symbol blocks the taps of the player for a short time,
  so that a player cannot find the symbol by tapping all symbols fast.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.Overlap.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the `"overlap:<id>"`
  PubSub topic as `{:overlap_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "overlap",
    state_message: :overlap_state,
    lobby_topic: "overlap_lobby",
    store: Octomocto.Overlap.Store,
    context: Octomocto.Overlap

  alias Octomocto.RaceServer
  alias Octomocto.Overlap.Deck

  # How long the taps of a player are blocked after a wrong symbol. The page
  # blocks them for 1 second. The block here is a bit shorter, so that the
  # first tap after the block on the page is not lost on the way.
  @freeze_ms 800

  @impl true
  def init_settings(_config), do: %{}

  # The system time in ms until which the taps of the player are blocked
  @impl true
  def new_player(player), do: Map.put(player, :frozen_until, 0)

  @impl true
  def reset_player(player), do: %{player | frozen_until: 0}

  @impl true
  def new_field(state) do
    [pile, card | deck] = Deck.shuffled()

    Map.merge(state, %{
      # The top card of the pile, and the card that the players try to win
      pile: pile,
      card: card,
      deck: deck,
      # The last symbol that a player found, with the player and its color
      last: nil
    })
  end

  # Two players can tap the common symbol at the same time. The first tap
  # wins the card. The second tap is for cards that are not on the table
  # any more, so it is ignored and does not block the player.
  @impl true
  def handle_move({:tap, player_id, pile, card, symbol}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    cond do
      not RaceServer.started?(state) or state.pile.id != pile or state.card.id != card or
          RaceServer.now() < state.players[player_id].frozen_until ->
        {:ignore, :ok, state}

      symbol == Deck.common(state.pile, state.card) ->
        state =
          state
          |> update_in([:players, player_id, :score], &(&1 + 1))
          |> Map.put(:last, %{
            player_id: player_id,
            color: state.players[player_id].color,
            symbol: symbol
          })
          |> next_card()

        {:publish, :ok, state}

      true ->
        state = put_in(state.players[player_id].frozen_until, RaceServer.now() + @freeze_ms)
        {:store, :ok, state}
    end
  end

  def handle_move({:tap, _player_id, _pile, _card, _symbol}, state), do: {:ignore, :ok, state}

  # The won card goes on the pile. With no cards left in the deck, the game
  # ends, and the won card stays on the table with the old pile card.
  defp next_card(%{deck: []} = state), do: RaceServer.finish(state)

  defp next_card(%{deck: [next | deck]} = state) do
    %{state | pile: state.card, card: next, deck: deck}
  end

  @impl true
  def lobby_settings(_state), do: %{}

  @impl true
  def result_settings(_state), do: %{"symbols" => 8}

  @impl true
  def public_field(state) do
    started? = RaceServer.started?(state)

    %{
      # Do not show the cards before the start (also during the countdown),
      # so that nobody can look for the symbol early.
      pile: if(started?, do: state.pile),
      card: if(started?, do: state.card),
      # The cards that the players can still win: the deck, and the card on
      # the table
      cards_left: if(state.finished_at, do: 0, else: length(state.deck) + 1),
      last: state.last
    }
  end
end
