defmodule OctomoctoWeb.LocaleControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  alias Octomocto.Repo

  describe "GET /locale/:locale" do
    test "remembers the language and opens the page", %{conn: conn} do
      conn = get(conn, ~p"/locale/en?#{[to: "/memory"]}")

      assert redirected_to(conn) == "/memory"
      assert get_session(conn, "locale") == "en"
    end

    test "remembers the language for the user", %{conn: conn} do
      %{conn: conn, user: user} = register_and_log_in_user(%{conn: conn})

      get(conn, ~p"/locale/pt?#{[to: "/pt/memory"]}")

      assert Repo.reload!(user).preferred_locale == "pt"
    end

    test "does not remember a language that the site does not have", %{conn: conn} do
      conn = get(conn, ~p"/locale/xx?#{[to: "/memory"]}")

      assert redirected_to(conn) == "/memory"
      refute get_session(conn, "locale")
    end

    test "does not open a different site", %{conn: conn} do
      conn = get(conn, ~p"/locale/en?#{[to: "//evil.example"]}")
      assert redirected_to(conn) == "/"
    end
  end
end
