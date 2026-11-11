defmodule OctomoctoWeb.ProfileControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Guests

  test "a new guest has the Profile link to /profile", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, ~s(#guest-menu #profile-link[href="/profile"]))
  end

  test "a new guest sees the sign-in forms", %{conn: conn} do
    conn = get(conn, ~p"/profile")
    assert html_response(conn, 200) =~ ~s(id="guest-sign-in-page")
  end

  test "a guest with results goes to the profile page", %{conn: conn} do
    conn = get(conn, ~p"/")
    Guests.save([%{guest_id: get_session(conn, "guest_id"), name: "Guest"}], DateTime.utc_now())

    conn = get(conn, ~p"/profile")

    assert redirected_to(conn) =~ ~r"^/players/\w+$"
  end

  describe "a signed-in user" do
    setup :register_and_log_in_user

    test "goes to the profile page", %{conn: conn, user: user} do
      conn = get(conn, ~p"/profile")
      assert redirected_to(conn) == ~p"/players/#{user.public_id}"
    end
  end
end
