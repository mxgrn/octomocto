defmodule OctomoctoWeb.UserSessionController do
  use OctomoctoWeb, :controller

  alias Octomocto.Accounts
  alias Octomocto.Accounts.TelegramAuth
  alias OctomoctoWeb.UserAuth

  # The home page has the same sign-in forms. This page is for the redirects
  # from pages that need a (recent) sign-in.
  def new(conn, _params) do
    render(conn, :new)
  end

  # magic link sign-in
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info =
      case params do
        %{"_action" => "confirmed"} -> "Email confirmed successfully."
        _ -> "Welcome back!"
      end

    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/signin")
    end
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}}) do
    case Accounts.get_or_register_user(email) do
      {:ok, user} ->
        Accounts.deliver_login_instructions(user, &url(~p"/signin/#{&1}"))

        conn
        |> put_flash(:info, "We sent a sign-in link to #{user.email}.")
        |> redirect(to: return_path(conn))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, "Enter a valid email.")
        |> redirect(to: return_path(conn))
    end
  end

  def confirm(conn, %{"token" => token}) do
    if user = Accounts.get_user_by_magic_link_token(token) do
      form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

      conn
      |> assign(:user, user)
      |> assign(:form, form)
      |> render(:confirm)
    else
      conn
      |> put_flash(:error, "Magic link is invalid or it has expired.")
      |> redirect(to: ~p"/signin")
    end
  end

  # The Telegram Login Widget sends the user here
  def telegram(conn, params) do
    with {:ok, attrs} <- TelegramAuth.verify(params),
         {:ok, user} <- Accounts.sign_in_with_telegram(attrs) do
      conn
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      _ ->
        conn
        |> put_flash(:error, "Telegram sign-in failed. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out successfully.")
    |> UserAuth.log_out_user()
  end

  # A signed-in user is here to sign in again (see `UserAuth.require_sudo_mode/2`)
  defp return_path(conn) do
    if conn.assigns.current_scope, do: ~p"/signin", else: ~p"/"
  end
end
