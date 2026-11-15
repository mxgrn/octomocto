defmodule OctomoctoWeb.ResultsPreviewTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.ResultsPreview

  test "build/2 gives 30 points, the 5 newest as the latest, and the lowest time as the best" do
    preview = ResultsPreview.build([60_000, 90_000], lower_better: true)

    assert length(preview.trend) == 30
    newest = preview.trend |> Enum.take(-5) |> Enum.reverse()
    assert Enum.map(preview.latest, & &1.id) == Enum.map(newest, & &1.id)
    assert preview.best.value == preview.trend |> Enum.map(& &1.value) |> Enum.min()
  end

  test "build/2 gives the highest score as the best, not more than the max" do
    preview = ResultsPreview.build([10], max: 10)

    values = Enum.map(preview.trend, & &1.value)
    assert Enum.max(values) <= 10
    assert preview.best.value == Enum.max(values)
  end
end
