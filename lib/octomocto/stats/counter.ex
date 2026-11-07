defmodule Octomocto.Stats.Counter do
  @moduledoc """
  Keeps the number of all games played in memory, so that a page does not
  query the database for it (see `Octomocto.Stats.games_played/0`).

  At start, the process counts the games in the database once. Then it adds
  one for each `{:game_finished}` (see `Octomocto.Stats.subscribe/0`), which
  comes from all nodes. In the test environment, it does not query the
  database and starts at zero.
  """
  use GenServer

  alias Octomocto.Stats

  @key {__MODULE__, :counter}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Gives the number of all games played, from memory."
  def get, do: :counters.get(:persistent_term.get(@key), 1)

  @impl true
  def init(_opts) do
    # One counter for the life of the node. A new one only when there is none,
    # because each write to :persistent_term is costly.
    ref =
      with nil <- :persistent_term.get(@key, nil) do
        ref = :counters.new(1, [:write_concurrency])
        :persistent_term.put(@key, ref)
        ref
      end

    # Before the count, so that no game finishes between the two unseen
    Stats.subscribe()
    {:ok, ref, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, ref) do
    if Application.get_env(:octomocto, :load_games_played, true) do
      :counters.put(ref, 1, Stats.games_played())
    end

    {:noreply, ref}
  end

  @impl true
  def handle_info({:game_finished}, ref) do
    :counters.add(ref, 1, 1)
    {:noreply, ref}
  end
end
