defmodule OctomoctoWeb.UserSessionController do
  use OctomoctoWeb, :controller

  alias Octomocto.Accounts
  alias Octomocto.Accounts.GoogleAuth
  alias Octomocto.Accounts.TelegramAuth
  alias OctomoctoWeb.Locale
  alias OctomoctoWeb.Turnstile
  alias OctomoctoWeb.UserAgent
  alias OctomoctoWeb.UserAuth

  plug OctomoctoWeb.SiteBanners when action in [:new, :confirm]

  # Marks the browser that asked for a magic link. When the link opens in the same
  # browser, we sign the user in at once. Email link scanners do not have this cookie,
  # so they get the confirmation page and cannot use up the token.
  @magic_link_cookie "_octomocto_web_magic_link_email"
  @magic_link_cookie_options [sign: true, max_age: 24 * 60 * 60, same_site: "Lax"]

  # The home page has the same sign-in forms. This page is for the redirects
  # from pages that need a (recent) sign-in.
  def new(conn, _params) do
    render(conn, :new,
      page_title: gettext("Sign in"),
      languages: Locale.languages(:all, conn.assigns.locale, ~p"/signin")
    )
  end

  # magic link sign-in
  def create(conn, %{"user" => %{"token" => token} = user_params} = params) do
    info = if params["_action"] == "confirmed", do: "Email confirmed successfully."

    log_in_by_magic_link(conn, token, user_params, info)
  end

  # magic link request
  def create(conn, %{"user" => %{"email" => email}} = params) do
    with :ok <- Turnstile.verify(params),
         {:ok, user} <- Accounts.get_or_register_user(email, conn.assigns.guest_name) do
      device = conn |> get_req_header("user-agent") |> List.first() |> UserAgent.describe()
      Accounts.deliver_login_instructions(user, &url(~p"/signin/#{&1}"), device)

      conn
      |> put_resp_cookie(@magic_link_cookie, user.email, @magic_link_cookie_options)
      |> put_flash(
        :info,
        gettext(
          "We sent a sign-in link to %{email}. If you do not see it, look in your spam folder.",
          email: user.email
        )
      )
      |> redirect(to: return_path(conn))
    else
      {:error, :turnstile} ->
        conn
        |> put_flash(:error, gettext("Please confirm that you are not a robot."))
        |> redirect(to: return_path(conn))

      {:error, _changeset} ->
        conn
        |> put_flash(:error, gettext("Enter a valid email."))
        |> redirect(to: return_path(conn))
    end
  end

  def confirm(conn, %{"token" => token}) do
    conn = fetch_cookies(conn, signed: [@magic_link_cookie])
    user = Accounts.get_user_by_magic_link_token(token)

    cond do
      user && conn.cookies[@magic_link_cookie] == user.email ->
        info = if user.confirmed_at, do: nil, else: "Email confirmed successfully."
        log_in_by_magic_link(conn, token, %{"remember_me" => "true"}, info)

      user ->
        form = Phoenix.Component.to_form(%{"token" => token}, as: "user")

        conn
        |> assign(:user, user)
        |> assign(:form, form)
        |> render(:confirm)

      # Probably a link that was already used
      conn.assigns.current_scope ->
        conn
        |> put_flash(:info, "You are already signed in.")
        |> redirect(to: ~p"/")

      email = Accounts.get_magic_link_token_email(token) ->
        form = Phoenix.Component.to_form(%{"email" => email}, as: "user")
        render(conn, :expired, form: form)

      true ->
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

  # The "Continue with Google" button sends the user here. The state in
  # the session makes sure that the callback comes from a sign-in that
  # this browser started.
  def google(conn, _params) do
    state = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

    conn
    |> put_session(:google_auth_state, state)
    |> redirect(external: GoogleAuth.authorize_url(google_redirect_uri(), state))
  end

  # Google sends the user here after the user picks an account
  def google_callback(conn, %{"state" => state, "code" => code}) do
    saved_state = get_session(conn, :google_auth_state)
    conn = delete_session(conn, :google_auth_state)

    with true <- is_binary(saved_state) and Plug.Crypto.secure_compare(saved_state, state),
         {:ok, attrs} <- GoogleAuth.fetch_user(code, google_redirect_uri()),
         {:ok, user} <- Accounts.sign_in_with_google(attrs, conn.assigns.guest_name) do
      conn
      |> put_flash(:info, "Welcome!")
      |> UserAuth.log_in_user(user, %{"remember_me" => "true"})
    else
      {:error, :conflict} ->
        conn
        |> put_flash(:error, "This email belongs to an account with a different Google account.")
        |> redirect(to: ~p"/")

      _ ->
        google_failed(conn)
    end
  end

  # The user cancelled on the Google page
  def google_callback(conn, %{"error" => "access_denied"}), do: redirect(conn, to: ~p"/")

  def google_callback(conn, _params), do: google_failed(conn)

  defp google_failed(conn) do
    conn
    |> put_flash(:error, "Google sign-in failed. Please try again.")
    |> redirect(to: ~p"/")
  end

  defp google_redirect_uri, do: url(~p"/auth/google/callback")

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Signed out successfully.")
    |> UserAuth.log_out_user()
  end

  # A returning user gets no flash, so `info` can be nil
  defp log_in_by_magic_link(conn, token, user_params, info) do
    case Accounts.login_user_by_magic_link(token) do
      {:ok, {user, _expired_tokens}} ->
        conn
        |> delete_resp_cookie(@magic_link_cookie, @magic_link_cookie_options)
        |> then(&if(info, do: put_flash(&1, :info, info), else: &1))
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The link is invalid or it has expired.")
        |> redirect(to: ~p"/signin")
    end
  end

  # A signed-in user can open /signin to sign in again. The page is in the
  # language of the form.
  defp return_path(conn) do
    path = if conn.assigns.current_scope, do: ~p"/signin", else: ~p"/"
    Locale.path(conn.assigns.locale, path)
  end
end
