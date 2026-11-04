defmodule Octomocto.SeatsTest do
  use ExUnit.Case, async: true

  alias Octomocto.Seats

  defp add(state) do
    Seats.add(state, self(), nil, nil, nil, false, %{})
  end

  test "the first player is the creator, and nobody takes its place after it is removed" do
    {first, state} = add(Seats.new("game", %{players: 2, public: false}))

    {_second, state} = state |> Seats.remove(first) |> add()

    assert state.creator == first
  end

  test "a game with creator: false in the config has no creator" do
    {_player, state} = add(Seats.new("game", %{players: 2, public: false, creator: false}))

    assert state.creator == false
  end

  test "a state from before the creator has no creator" do
    state = Seats.new("game", %{players: 2, public: false}) |> Map.delete(:creator)

    {_player, state} = state |> Seats.restore() |> add()

    assert state.creator == false
  end
end
