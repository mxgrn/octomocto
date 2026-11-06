defmodule Octomocto.Memory.ThemesTest do
  use ExUnit.Case, async: true

  alias Octomocto.Memory.Themes

  test "by_use/1 puts the most used themes first and keeps the order of the others" do
    names = %{"space" => 1, "cats" => 3} |> Themes.by_use() |> Enum.map(& &1.name)
    others = Themes.list() |> Enum.map(& &1.name) |> Kernel.--(["cats", "space"])

    assert names == ["cats", "space" | others]
  end
end
