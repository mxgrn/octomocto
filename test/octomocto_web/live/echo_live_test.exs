defmodule OctomoctoWeb.EchoLiveTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  for locale <- ~w(de ru fr uk pl it es ja vi tr ar) do
    test "/#{locale}/echo shows Echo in the language", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/#{unquote(locale)}/echo")

      assert has_element?(view, "#new-game")
      # The logo goes to the front page in the same language
      assert has_element?(view, ~s|a[href="/#{unquote(locale)}"]|)
    end
  end

  test "the page links to the other memory games", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/echo")

    assert has_element?(view, ~s|#more-games a[href="/memory"]|)
    refute has_element?(view, ~s|#more-games a[href="/echo"]|)
  end
end
