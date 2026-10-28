defmodule Octomocto.OverlapTest do
  use Octomocto.DataCase, async: true

  import Octomocto.GameHelpers

  alias Octomocto.Overlap
  alias Octomocto.Overlap.{Deck, Result, Store}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(overlap_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    {:ok, player_id, _} = Overlap.join(id)
    %{id: id, player_id: player_id}
  end

  defp tap_symbol(id, player_id, symbol \\ :common) do
    %{pile: pile, card: card} = Store.read(id)
    symbol = if symbol == :common, do: Deck.common(pile, card), else: symbol
    Overlap.tap(id, player_id, pile.id, card.id, symbol)
    {:ok, nil, state} = Overlap.watch(id)
    state
  end

  defp wrong_symbol(id) do
    %{pile: pile, card: card} = Store.read(id)
    common = Deck.common(pile, card)
    Enum.find_value(card.symbols, &(&1.symbol != common and &1.symbol))
  end

  test "the common symbol wins the card, and it goes on the pile",
       %{id: id, player_id: player_id} do
    card = Store.read(id).card

    assert %{players: [%{score: 1}], pile: ^card} = tap_symbol(id, player_id)
  end

  test "a wrong symbol blocks the taps of the player until a restart",
       %{id: id, player_id: player_id} do
    tap_symbol(id, player_id, wrong_symbol(id))

    assert %{players: [%{score: 0}]} = tap_symbol(id, player_id)

    Overlap.restart(id, player_id)
    {:ok, nil, _} = Overlap.watch(id)

    assert %{players: [%{score: 1}]} = tap_symbol(id, player_id)
  end

  test "the game ends when the deck is empty, and saves the result",
       %{id: id, player_id: player_id} do
    for _ <- 1..(length(Deck.cards()) - 1), do: tap_symbol(id, player_id)

    assert {:ok, nil, %{finished: true, cards_left: 0}} = Overlap.watch(id)
    assert [%Result{settings: %{"symbols" => 8, "players" => 1}}] = Repo.all(Result)
  end
end
