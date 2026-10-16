defmodule Octomocto.Repo.Migrations.AddAccuracyToMatchResults do
  use Ecto.Migration

  def change do
    # The checked flips of the player (see `Octomocto.Memory.accuracy/1`).
    # Nil for the results from before the accuracy.
    alter table(:match_results) do
      add :correct, :integer
      add :errors, :integer
    end
  end
end
