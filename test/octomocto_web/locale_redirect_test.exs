defmodule OctomoctoWeb.LocaleRedirectTest do
  use OctomoctoWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Octomocto.Accounts

  # The plug does not redirect a request without a User-Agent (bots)
  defp browser(conn, accept_language) do
    conn
    |> put_req_header("user-agent", "Mozilla/5.0")
    |> put_req_header("accept-language", accept_language)
  end

  test "sends a browser in Portuguese to the Portuguese page, with the query", %{conn: conn} do
    conn = conn |> browser("pt-BR,pt;q=0.9") |> get(~p"/memory?size=16")
    assert redirected_to(conn) == "/pt/memory?size=16"
  end

  test "sends the front page to the localized front page", %{conn: conn} do
    conn = conn |> browser("de-DE") |> get(~p"/")
    assert redirected_to(conn) == "/de"
  end

  test "keeps a page without a translation in English", %{conn: conn} do
    conn = conn |> browser("pt-BR") |> get(~p"/trains")
    assert html_response(conn, 200)
  end

  test "keeps an English browser on the English page", %{conn: conn} do
    conn = conn |> browser("en-US") |> get(~p"/memory")
    assert html_response(conn, 200)
  end

  test "uses the language picked in the footer before the browser language", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"locale" => "en"})
      |> browser("pt-BR")
      |> get(~p"/memory")

    assert html_response(conn, 200)
  end

  test "does not use a different language when the picked one has no translation", %{
    conn: conn
  } do
    conn =
      conn
      |> init_test_session(%{"locale" => "ru"})
      |> browser("pt-BR")
      |> get(~p"/trains")

    assert html_response(conn, 200)
  end

  test "uses the language of the user before the language in the session", %{conn: conn} do
    user = Octomocto.AccountsFixtures.user_fixture()
    Accounts.update_user_preferred_locale(user, "de")

    conn =
      conn
      |> log_in_user(user)
      |> put_session("locale", "pt")
      |> browser("pt-BR")
      |> get(~p"/memory")

    assert redirected_to(conn) == "/de/memory"
  end

  test "does not redirect a bot", %{conn: conn} do
    conn =
      conn
      |> put_req_header("user-agent", "Googlebot/2.1")
      |> put_req_header("accept-language", "pt-BR")
      |> get(~p"/memory")

    assert html_response(conn, 200)
  end

  test "does not change the language of a URL with a prefix", %{conn: conn} do
    conn = conn |> browser("pt-BR") |> get(~p"/ru/memory")
    assert html_response(conn, 200)
  end

  test "redirects a live navigation to a page with a translation", %{conn: conn} do
    conn = conn |> init_test_session(%{"locale" => "pt"}) |> browser("en")
    {:ok, view, _html} = live(conn, ~p"/trains")

    assert {:error, {:redirect, %{to: "/pt/memory"}}} = live_redirect(view, to: ~p"/memory")
  end
end
