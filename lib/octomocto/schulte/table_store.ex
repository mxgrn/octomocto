defmodule Octomocto.Schulte.TableStore do
  @moduledoc """
  The copies of the running Schulte games, see `Octomocto.GameStore`.

  Not "Schulte.Store": a node with older code has a table with that name for
  the games of Nimble Mosaic (its old name was "Schulte"). In a deploy, a new
  node copies the tables of the old node with the same names.
  """
  use Octomocto.GameStore
end
