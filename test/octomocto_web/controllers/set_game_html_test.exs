defmodule OctomoctoWeb.SetGameHTMLTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.SetGameHTML

  test "card_names/0 gives the name of each card, by its number" do
    Gettext.with_locale(OctomoctoWeb.Gettext, "en", fn ->
      names = SetGameHTML.card_names()

      assert length(names) == 81
      assert Enum.at(names, 0) == "1 red solid diamond"
      assert Enum.at(names, 80) == "3 purple open squiggles"
    end)
  end
end
