defmodule Octomocto.Trains.CampaignTest do
  use ExUnit.Case, async: true

  alias Octomocto.Trains.Campaign

  test "the levels go from 4 switches at the normal pace to the hardest settings" do
    levels = Campaign.levels()

    assert length(levels) == 25
    assert %{switch_count: 4, pace: "normal"} = hd(levels)
    assert %{switch_count: 12, pace: "expert", trains_per_house: 7} = List.last(levels)
  end

  test "each level permits at least one error" do
    for level <- Campaign.levels() do
      assert Campaign.pass_count(level.trains) < level.trains
    end
  end

  test "the pace never becomes slower" do
    paces =
      Enum.map(
        Campaign.levels(),
        &Enum.find_index(Octomocto.Trains.paces(), fn p -> p == &1.pace end)
      )

    assert paces == Enum.sort(paces)
  end
end
