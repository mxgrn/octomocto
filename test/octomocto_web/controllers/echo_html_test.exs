defmodule OctomoctoWeb.EchoHTMLTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.EchoHTML

  test "elm_plurals/0 gives each plural form of the language, by its index" do
    Gettext.with_locale(OctomoctoWeb.Gettext, "en", fn ->
      assert EchoHTML.elm_plurals()["{count} pads"] == ["{count} pad", "{count} pads"]
    end)

    Gettext.with_locale(OctomoctoWeb.Gettext, "ru", fn ->
      assert length(EchoHTML.elm_plurals()["{count} taps"]) == 3
    end)
  end
end
