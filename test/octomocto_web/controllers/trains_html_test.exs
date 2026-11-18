defmodule OctomoctoWeb.TrainsHTMLTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.TrainsHTML

  test "elm_plurals/0 gives each plural form of the language, by its index" do
    Gettext.with_locale(OctomoctoWeb.Gettext, "en", fn ->
      assert TrainsHTML.elm_plurals()["{count} errors"] == ["{count} error", "{count} errors"]
    end)

    Gettext.with_locale(OctomoctoWeb.Gettext, "ru", fn ->
      assert length(TrainsHTML.elm_plurals()["{count} switches"]) == 3
    end)
  end
end
