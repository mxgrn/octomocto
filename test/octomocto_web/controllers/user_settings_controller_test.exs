defmodule OctomoctoWeb.UserSettingsControllerTest do
  use OctomoctoWeb.ConnCase, async: true

  alias Octomocto.Accounts
  import Octomocto.AccountsFixtures

  defp signed_in_user_id(conn) do
    {user, _inserted_at} = Accounts.get_user_by_session_token(get_session(conn, :user_token))
    user.id
  end

  describe "GET /settings" do
    setup :register_and_log_in_user

    test "renders the email form and the Telegram widget", %{conn: conn} do
      document = conn |> get(~p"/settings") |> html_response(200) |> LazyHTML.from_document()

      assert Enum.any?(LazyHTML.query(document, "#update_email"))
      assert Enum.any?(LazyHTML.query(document, "#telegram-connect"))
    end

    test "redirects if the user is not signed in" do
      conn = get(build_conn(), ~p"/settings")
      assert redirected_to(conn) == ~p"/signin"
    end
  end

  describe "PUT /settings (change email form)" do
    setup :register_and_log_in_user

    test "sends a confirmation link to the new email", %{conn: conn, user: user} do
      conn =
        put(conn, ~p"/settings", %{
          "action" => "update_email",
          "user" => %{"email" => unique_user_email()}
        })

      assert redirected_to(conn) == ~p"/settings"

      assert Octomocto.Repo.get_by(Accounts.UserToken,
               user_id: user.id,
               context: "change:#{user.email}"
             )
    end

    test "rejects the email of a user that cannot be merged", %{conn: conn} do
      conn =
        put(conn, ~p"/settings", %{
          "action" => "update_email",
          "user" => %{"email" => user_fixture().email}
        })

      assert html_response(conn, 200) =~ "has already been taken"
    end
  end

  describe "GET /settings/confirm-email/:token" do
    test "merges into the older user with this email and signs in as it", %{conn: conn} do
      older = user_fixture()
      user = telegram_user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: older.email}, nil, url)
        end)

      conn = conn |> log_in_user(user) |> get(~p"/settings/confirm-email/#{token}")

      assert redirected_to(conn) == ~p"/settings"
      assert signed_in_user_id(conn) == older.id
    end
  end

  describe "GET /settings/telegram" do
    setup :register_and_log_in_user

    test "connects the Telegram account", %{conn: conn, user: user} do
      conn = get(conn, ~p"/settings/telegram", telegram_params(%{"id" => "42"}))

      assert redirected_to(conn) == ~p"/settings"
      assert Accounts.get_user!(user.id).telegram_id == 42
    end

    test "rejects params with a wrong hash", %{conn: conn, user: user} do
      params = %{telegram_params() | "id" => "42"}

      get(conn, ~p"/settings/telegram", params)

      refute Accounts.get_user!(user.id).telegram_id
    end
  end

  describe "GET /settings/telegram for a user that is newer than the Telegram user" do
    test "merges into the older Telegram user and signs in as it", %{conn: conn} do
      older = telegram_user_fixture(%{"id" => "42"})
      conn = log_in_user(conn, user_fixture())

      conn = get(conn, ~p"/settings/telegram", telegram_params(%{"id" => "42"}))

      assert redirected_to(conn) == ~p"/settings"
      assert signed_in_user_id(conn) == older.id
    end
  end
end
