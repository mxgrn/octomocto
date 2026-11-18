defmodule Octomocto.Repo.Migrations.ScaleTrainsCampaignProgressToNewLevels do
  use Ecto.Migration

  # The Trains campaign got a new list of 25 levels in place of the 20 old
  # ones (see `Octomocto.Trains.Campaign`). The progress of a player keeps
  # its level numbers: a player who passed the old levels 1 to N has the
  # new levels 1 to N as passed. A level with the same number can have
  # another number of trains now, so the best number of trains of each row
  # changes to the same share of the new number of trains.
  #
  # {level, old trains, new trains} of the levels where the number changed
  @trains [
    {1, 8, 10},
    {2, 10, 20},
    {3, 14, 12},
    {4, 18, 24},
    {5, 26, 14},
    {6, 10, 16},
    {7, 15, 20},
    {8, 14, 22},
    {9, 10, 24},
    {10, 16, 26},
    {11, 18, 14},
    {12, 14, 16},
    {13, 26, 18},
    {14, 16, 22},
    {15, 14, 24},
    {16, 18, 26},
    {17, 26, 39},
    {18, 18, 14},
    {19, 26, 16},
    {20, 39, 24}
  ]

  def up do
    scale(fn {level, old, new} -> "(#{level}, #{old}, #{new})" end)
  end

  # The numbers that were rounded do not always come back
  def down do
    scale(fn {level, old, new} -> "(#{level}, #{new}, #{old})" end)
  end

  # A passed level stays at 90% or more (the share goes up to the next
  # train), and a level that is not passed stays below 90% (the share goes
  # down).
  defp scale(row) do
    execute """
    UPDATE trains_campaign_levels AS l
    SET best_correct =
      CASE
        WHEN l.completed_at IS NULL THEN FLOOR(l.best_correct * t.to_trains::numeric / t.from_trains)
        ELSE CEIL(l.best_correct * t.to_trains::numeric / t.from_trains)
      END
    FROM (VALUES #{Enum.map_join(@trains, ", ", row)}) AS t(level, from_trains, to_trains)
    WHERE l.level = t.level
    """
  end
end
