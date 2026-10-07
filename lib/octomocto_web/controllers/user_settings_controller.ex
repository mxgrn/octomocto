defmodule OctomoctoWeb.UserSettingsController do
  use OctomoctoWeb, :controller

  alias Octomocto.Accounts
  alias Octomocto.Accounts.TelegramAuth
  alias OctomoctoWeb.UserAuth

  import Phoenix.Component, only: [to_form: 1, to_form: 2]

  plug :assign_email_form
  plug :assign_display_name_form

  def edit(conn, _params) do
    render(conn, :edit)
  end

  def update(conn, %{"action" => "update_display_name"} = params) do
    %{"user" => user_params} = params

    case Accounts.update_user_display_name(conn.assigns.current_scope.user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Name changed successfully.")
        |> redirect(to: ~p"/settings")

      {:error, changeset} ->
        render(conn, :edit, display_name_form: to_form(changeset, action: :update))
    end
  end

  def update(conn, %{"action" => "update_email"} = params) do
    %{"user" => user_params} = params
    user = conn.assigns.current_scope.user

    case Accounts.change_user_email(user, user_params) do
      %{valid?: true} = changeset ->
        Accounts.deliver_user_update_email_instructions(
          Ecto.Changeset.apply_action!(changeset, :insert),
          user.email,
          &url(~p"/settings/confirm-email/#{&1}")
        )

        conn
        |> put_flash(:info, "We sent a confirmation link to the new email.")
        |> redirect(to: ~p"/settings")

      changeset ->
        render(conn, :edit, email_form: to_form(changeset, action: :insert))
    end
  end

  def confirm_email(conn, %{"token" => token}) do
    case Accounts.update_user_email(conn.assigns.current_scope.user, token) do
      {:ok, user} ->
        conn
        |> put_flash(:info, "Email changed successfully.")
        |> stay_signed_in(user)

      {:error, :conflict} ->
        conn
        |> put_flash(:error, "This email belongs to a different account that has Telegram.")
        |> redirect(to: ~p"/settings")

      {:error, _} ->
        conn
        |> put_flash(:error, "Email change link is invalid or it has expired.")
        |> redirect(to: ~p"/settings")
    end
  end

  # The Telegram Login Widget on the settings page sends the user here
  def connect_telegram(conn, params) do
    with {:ok, attrs} <- TelegramAuth.verify(params),
         {:ok, user} <- Accounts.connect_telegram(conn.assigns.current_scope.user, attrs) do
      conn
      |> put_flash(:info, "Telegram connected successfully.")
      |> stay_signed_in(user)
    else
      {:error, :conflict} ->
        conn
        |> put_flash(
          :error,
          "This Telegram account belongs to a different account that has an email."
        )
        |> redirect(to: ~p"/settings")

      _ ->
        conn
        |> put_flash(:error, "Telegram connection failed. Please try again.")
        |> redirect(to: ~p"/settings")
    end
  end

  # After a merge, the older user stays. If it is not the current user, the
  # current user does not exist anymore, so we sign in as the older user.
  defp stay_signed_in(conn, user) do
    if user.id == conn.assigns.current_scope.user.id do
      redirect(conn, to: ~p"/settings")
    else
      conn
      |> put_session(:user_return_to, ~p"/settings")
      |> UserAuth.log_in_user(user)
    end
  end

  defp assign_display_name_form(conn, _opts) do
    user = conn.assigns.current_scope.user
    assign(conn, :display_name_form, to_form(Accounts.change_user_display_name(user)))
  end

  defp assign_email_form(conn, _opts) do
    user = conn.assigns.current_scope.user
    assign(conn, :email_form, to_form(Accounts.change_user_email(user)))
  end
end
