defmodule OctomoctoWeb.NoticesTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Notices

  defp notice(id, opts \\ []) do
    %{
      id: id,
      text: "Max invites you to Memory",
      actions: [
        %{id: "join", label: "Join", href: Keyword.get(opts, :href)},
        %{id: "later", label: "Not now", href: nil}
      ],
      expires_at: Keyword.get(opts, :expires_at)
    }
  end

  test "a guest gets a notice from notify/3, and closes it with OK", %{conn: conn} do
    conn = get(conn, ~p"/")
    {:ok, view, _html} = live(conn)

    id = Notices.notify({:guest, get_session(conn, "guest_id")}, "The site restarts soon.")
    assert has_element?(view, "#notice-#{id}", "The site restarts soon.")

    view |> element("#notice-#{id}-ok") |> render_click()
    refute has_element?(view, "#notice-#{id}")
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "sees the first notice over the page, and the others wait", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      Notices.push({:user, user.id}, notice("first"))
      Notices.push({:user, user.id}, notice("second"))

      assert has_element?(view, "#notice-float #notice-first", "+1")
      refute has_element?(view, "#notice-second")
    end

    test "closes a notice on all pages with a button, and the next one shows",
         %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")
      {:ok, other, _html} = live(conn, ~p"/memory")
      Notices.push({:user, user.id}, notice("first"))
      Notices.push({:user, user.id}, notice("second"))

      view |> element("#notice-first-later") |> render_click()

      assert has_element?(other, "#notice-second")
      refute has_element?(other, "#notice-first")
    end

    test "goes to the link of a button", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")
      Notices.push({:user, user.id}, notice("first", href: "/memory/abc"))

      assert {:error, {:redirect, %{to: "/memory/abc"}}} =
               view |> element("#notice-first-join") |> render_click()
    end

    test "does not show a notice that expired", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/")

      Notices.push(
        {:user, user.id},
        notice("old", expires_at: System.system_time(:millisecond) - 1)
      )

      refute has_element?(view, "#notice-float")
    end

    test "sees a notice in the bar of a game page in place of the settings",
         %{conn: conn, user: user} do
      {:ok, view, _html} =
        live_isolated(conn, OctomoctoWeb.GameBarLive,
          session: %{"kind" => "snap", "id" => "game", "locale" => "en"}
        )

      Notices.push({:user, user.id}, notice("first"))

      assert has_element?(view, "#game-bar #notice-first")
    end
  end
end
