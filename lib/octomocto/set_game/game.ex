defmodule Octomocto.SetGame.Game do
  @moduledoc """
  One multiplayer Set game. The table has 12 cards from a deck of 81, or
  of 27 cards with one same attribute in the easy mode (see
  `Octomocto.SetGame.Deck`). All players look for sets at the same time,
  and the first player who claims a set gets one point. The cards of the
  set go off the table, and cards from the deck take their places. A wrong
  claim changes nothing. Nobody sees the cards before the countdown is
  over.

  When the table has no set, 3 more cards come from the deck until it has
  one. The next set then only goes off the table, and the last cards move
  into its places, so that the table goes back to 12 cards. The table is
  finished when the deck is empty and the table has no set.

  The players, the clock, the lists of the settings page and the copy in
  `Octomocto.SetGame.Store` are the same as in the other games, see
  `Octomocto.RaceServer`. Each change is broadcast on the
  `"set_game:<id>"` PubSub topic as `{:set_state, state}`.
  """
  use Octomocto.RaceServer,
    topic: "set_game",
    state_message: :set_state,
    lobby_topic: "set_lobby",
    store: Octomocto.SetGame.Store,
    context: Octomocto.SetGame

  alias Octomocto.RaceServer
  alias Octomocto.SetGame.Deck

  @impl true
  def init_settings(%{mode: mode}) when mode in ~w(easy normal), do: %{mode: mode}

  # A state from before the modes
  @impl true
  def restore(state), do: Map.put_new(state, :mode, "normal")

  @impl true
  def new_field(state) do
    {table, deck} = Enum.split(Deck.shuffled(state.mode), Deck.table())

    # The last set that a player found
    Map.merge(state, %{table: table, deck: deck, last_set: nil})
    |> deal_until_set()
  end

  # Two players can claim the same cards at the same time. The first claim
  # takes the cards, and the second one is not a set on the table any more.
  @impl true
  def handle_move({:claim, player_id, cards}, state)
      when is_map_key(state.players, player_id) and state.finished_at == nil do
    if RaceServer.started?(state) and Enum.all?(cards, &(&1 in state.table)) and
         Deck.set?(cards) do
      state =
        state
        |> update_in([:players, player_id, :score], &(&1 + 1))
        |> Map.put(:last_set, %{player_id: player_id, cards: cards})
        |> take_set(cards)
        |> deal_until_set()

      {:publish, :ok, state}
    else
      {:ignore, :ok, state}
    end
  end

  def handle_move({:claim, _player_id, _cards}, state), do: {:ignore, :ok, state}

  # With no extra cards on the table, new cards from the deck take the
  # places of the set. Else the last cards of the table move into the
  # places of the set, so that the other cards stay where they are.
  defp take_set(state, cards) do
    if length(state.table) > Deck.table() or state.deck == [] do
      {head, tail} = Enum.split(state.table, length(state.table) - 3)
      %{state | table: fill(head, cards, tail -- cards)}
    else
      {new, deck} = Enum.split(state.deck, 3)
      %{state | table: fill(state.table, cards, new), deck: deck}
    end
  end

  # Puts the new cards into the places of the set cards, in order
  defp fill(table, set, new) do
    {table, []} =
      Enum.map_reduce(table, new, fn card, new ->
        if card in set, do: {hd(new), tl(new)}, else: {card, new}
      end)

    table
  end

  # Adds 3 cards while the table has no set. With no cards left in the
  # deck, the game ends.
  defp deal_until_set(state) do
    cond do
      Deck.any_set?(state.table) ->
        state

      state.deck == [] ->
        RaceServer.finish(state)

      true ->
        {new, deck} = Enum.split(state.deck, 3)
        deal_until_set(%{state | table: state.table ++ new, deck: deck})
    end
  end

  # The store can have a state from before the modes
  @impl true
  def lobby_settings(state), do: %{mode: Map.get(state, :mode, "normal")}

  @impl true
  def result_settings(state), do: %{"mode" => state.mode}

  @impl true
  def public_field(state) do
    %{
      # Do not show the cards before the start (also during the countdown),
      # so that nobody can look for sets early.
      table: if(RaceServer.started?(state), do: state.table, else: []),
      deck_left: length(state.deck),
      last_set: state.last_set
    }
  end
end
