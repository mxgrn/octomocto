defmodule Octomocto.Schulte.Store do
  @moduledoc """
  A copy of the state of each running Schulte game, in a Mnesia table in
  the memory of all cluster nodes. A game writes its state after each
  change. When the node of a game stops (for example, in a deploy), the
  game starts again on another node from this copy (see
  `Octomocto.Schulte.join/4`).
  """
  use Mnesiac.Store

  # The table must have the name of the module: mnesiac finds the tables to
  # copy to a new node by the store module.
  @table __MODULE__

  @impl true
  def store_options do
    # Each node adds its own copy when it joins the cluster (see `copy_store/0`)
    [attributes: [:id, :state], ram_copies: [node()]]
  end

  @impl true
  def resolve_conflict(_node) do
    copy_store()
  end

  # Only the game process writes its record, so a dirty write is safe and
  # does not wait for a transaction.
  def write(%{id: id} = state) do
    :mnesia.dirty_write({@table, id, state})
  end

  def read(id) do
    case :mnesia.dirty_read(@table, id) do
      [{@table, ^id, state}] -> state
      [] -> nil
    end
  end

  def delete(id) do
    :mnesia.dirty_delete(@table, id)
  end
end
