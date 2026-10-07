defmodule OctomoctoWeb.UserSessionControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  import Octomocto.AccountsFixtures
  alias Octomocto.Accounts

  defp has_element?(conn, selector) do
    conn
    |> html_response(200)
    |> LazyHTML.from_document()
    |> LazyHTML.query(selector)
    |> Enum.any?()
  end

  describe "GET /" do
    test "shows the sign-in forms to a guest", %{conn: conn} do
      conn = get(conn, ~p"/")

      assert has_element?(conn, "#sign-in-form")
      assert has_element?(conn, "#telegram-sign-in[data-auth-path='/auth/telegram']")
    end

    test "does not show the sign-in forms to a signed-in user", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> get(~p"/")

      refute has_element?(conn, "#sign-in-panel")
      assert has_element?(conn, "#sign-out-link")
    end
  end

  describe "GET /signin" do
    test "shows only the methods that a signed-in Telegram user has", %{conn: conn} do
      conn = conn |> log_in_user(telegram_user_fixture()) |> get(~p"/signin")

      assert has_element?(conn, "#telegram-sign-in")
      refute has_element?(conn, "#sign-in-form")
    end
  end

  describe "GET /signin/:token" do
    test "renders the confirmation page for an unconfirmed user", %{conn: conn} do
      {token, _hashed_token} = generate_user_magic_link_token(unconfirmed_user_fixture())

      conn = get(conn, ~p"/signin/#{token}")

      assert has_element?(conn, "#confirmation_form")
    end

    test "redirects for an invalid token", %{conn: conn} do
      conn = get(conn, ~p"/signin/invalid-token")

      assert redirected_to(conn) == ~p"/signin"
    end
  end

  describe "POST /signin - magic link request" do
    test "registers a new email and sends a magic link", %{conn: conn} do
      email = unique_user_email()

      conn = post(conn, ~p"/signin", %{"user" => %{"email" => email}})

      assert redirected_to(conn) == ~p"/"
      user = Accounts.get_user_by_email(email)
      assert Octomocto.Repo.get_by!(Accounts.UserToken, user_id: user.id).context == "login"
    end

    test "rejects an invalid email", %{conn: conn} do
      conn = post(conn, ~p"/signin", %{"user" => %{"email" => "not valid"}})

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Enter a valid email."
    end
  end

  describe "POST /signin - magic link" do
    test "signs the user in", %{conn: conn} do
      {token, _hashed_token} = generate_user_magic_link_token(user_fixture())

      conn = post(conn, ~p"/signin", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "confirms an unconfirmed user", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _hashed_token} = generate_user_magic_link_token(user)

      post(conn, ~p"/signin", %{"user" => %{"token" => token}})

      assert Accounts.get_user!(user.id).confirmed_at
    end

    test "redirects when the magic link is invalid", %{conn: conn} do
      conn = post(conn, ~p"/signin", %{"user" => %{"token" => "invalid"}})

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/signin"
    end
  end

  describe "GET /auth/telegram" do
    test "registers and signs in a new Telegram user", %{conn: conn} do
      conn = get(conn, ~p"/auth/telegram", telegram_params(%{"id" => "42"}))

      assert get_session(conn, :user_token)
      assert conn.resp_cookies["_octomocto_web_user_remember_me"]
      assert Accounts.get_user_by_telegram_id(42)
    end

    test "rejects params with a wrong hash", %{conn: conn} do
      params = %{telegram_params() | "id" => "42"}

      conn = get(conn, ~p"/auth/telegram", params)

      refute get_session(conn, :user_token)
      refute Accounts.get_user_by_telegram_id(42)
    end
  end

  describe "DELETE /signout" do
    test "signs the user out", %{conn: conn} do
      conn = conn |> log_in_user(user_fixture()) |> delete(~p"/signout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
    end
  end
end
