defmodule Octomocto.Guests do
  @moduledoc """
  The guests that finished a game (see `Octomocto.Guests.Guest`).
  """
  alias Octomocto.Guests.Guest
  alias Octomocto.Repo

  @doc """
  Saves the guests among the players of a finished game, before their
  results: a result refers to its guest. Each player is a map with
  `:name`, and `:guest_id` when the player is a guest with an id. A guest
  that is already saved keeps its row.
  """
  def save(players, now) do
    rows =
      for %{guest_id: id, name: name} <- players, id != nil and name != nil do
        %{id: id, name: name, inserted_at: now}
      end

    Repo.insert_all(Guest, rows, on_conflict: :nothing, conflict_target: :id)
  end

  @doc """
  The guest id of a player for its result. It is nil for a user, for a
  player from before the guest ids, and for a guest without a name, which
  `save/2` does not save.
  """
  def guest_id(%{guest_id: id, name: name}) when name != nil, do: id
  def guest_id(_player), do: nil
end
