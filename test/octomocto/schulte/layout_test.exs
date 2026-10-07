defmodule Octomocto.Schulte.LayoutTest do
  use ExUnit.Case, async: true

  alias Octomocto.Schulte.Layout

  test "generate/1 makes the given number of regions with labels on the board" do
    {width, height} = Layout.size()
    regions = Layout.generate(90)

    assert length(regions) == 90

    for %{label: [x, y, w, h]} <- regions do
      assert w > 0 and h > 0
      assert x >= 0 and y >= 0 and x + w <= width and y + h <= height
    end
  end

  test "generate/1 puts no label into the info box" do
    [bx, _by, _bw, bh] = Layout.info_box()

    for %{label: [x, y, w, _h]} <- Layout.generate(90) do
      assert x + w <= bx or y >= bh
    end
  end
end
