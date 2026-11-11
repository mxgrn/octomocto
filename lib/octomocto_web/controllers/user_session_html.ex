defmodule OctomoctoWeb.UserSessionHTML do
  use OctomoctoWeb, :html

  alias Octomocto.Accounts.GoogleAuth
  alias Octomocto.Accounts.TelegramAuth
  alias OctomoctoWeb.Turnstile

  embed_templates "user_session_html/*"

  @doc """
  Renders the sign-in forms: the Google button, the Telegram Login Widget
  and the magic link form.

  A signed-in user signs in again with only the methods that they have.
  """
  attr :current_scope, :map, default: nil

  def sign_in_panel(assigns) do
    user = assigns.current_scope && assigns.current_scope.user

    assigns =
      assigns
      |> assign(:user, user)
      |> assign(:form, to_form(%{"email" => user && user.email}, as: "user"))
      |> assign(:show_email?, is_nil(user) || !!user.email)
      |> assign(:show_telegram?, is_nil(user) || !!user.telegram_id)
      |> assign(:show_google?, GoogleAuth.enabled?() && (is_nil(user) || !!user.google_id))

    ~H"""
    <div
      id="sign-in-panel"
      class="space-y-5 rounded-3xl bg-white p-6 shadow-sm ring-1 ring-slate-200 dark:bg-base-200 dark:ring-white/10"
    >
      <div :if={@show_google? || @show_telegram?} class="space-y-3">
        <.google_button :if={@show_google?} />
        <.telegram_widget :if={@show_telegram?} id="telegram-sign-in" auth_path={~p"/auth/telegram"} />
      </div>

      <div
        :if={(@show_google? || @show_telegram?) && @show_email?}
        class="flex items-center gap-3 text-xs font-medium uppercase tracking-wider text-base-content/40"
      >
        <span class="h-px flex-1 bg-slate-200 dark:bg-white/10"></span>
        {gettext("or")} <span class="h-px flex-1 bg-slate-200 dark:bg-white/10"></span>
      </div>

      <.form
        :if={@show_email?}
        for={@form}
        id="sign-in-form"
        action={Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/signin")}
        class="space-y-3"
      >
        <.input
          field={@form[:email]}
          id="sign-in-email"
          type="email"
          placeholder={gettext("you@example.com")}
          autocomplete="username"
          spellcheck="false"
          readonly={!!@user}
          required
          class="w-full rounded-xl border-0 bg-slate-50 px-4 py-3 ring-1 ring-slate-200 transition placeholder:text-base-content/30 focus:bg-white focus:outline-none dark:bg-base-300 dark:ring-white/10 dark:focus:bg-base-300 focus:ring-2 focus:ring-indigo-500 read-only:text-base-content/60"
        />
        <.turnstile_widget id="sign-in-panel-turnstile" />
        <button
          id="sign-in-submit"
          class="w-full rounded-xl bg-indigo-600 px-4 py-3 font-medium text-white shadow-lg shadow-indigo-600/20 transition hover:bg-indigo-500"
        >
          {gettext("Email me a sign-in link")}
        </button>
      </.form>

      <p :if={local_mail_adapter?()} class="text-center text-xs text-base-content/50">
        Dev: see sent emails in <.link href="/dev/mailbox" class="underline">the mailbox</.link>.
      </p>
    </div>
    """
  end

  @doc """
  Renders a page of signed-in users as a guest sees it: what the page gives
  after sign-in, and the sign-in forms.
  """
  attr :title, :string, required: true
  slot :inner_block, required: true, doc: "what the page gives after sign-in"

  def guest_page(assigns) do
    ~H"""
    <div id="guest-sign-in-page" class="mx-auto max-w-md space-y-6 py-10">
      <div class="space-y-3 text-center">
        <h1 class="text-3xl font-semibold tracking-tight">{@title}</h1>
        <p class="text-base-content/70">{render_slot(@inner_block)}</p>
      </div>
      <.sign_in_panel />
    </div>
    """
  end

  @doc """
  Renders the "Continue with Google" button, in the style of Google's
  branding guidelines: https://developers.google.com/identity/branding-guidelines
  """
  def google_button(assigns) do
    ~H"""
    <div class="flex justify-center">
      <a
        id="google-sign-in"
        href={~p"/auth/google"}
        class="inline-flex h-10 items-center gap-3 rounded-full border border-[#747775] bg-white px-4 text-sm font-medium text-[#1f1f1f] transition hover:bg-slate-50 hover:shadow-sm dark:border-[#8e918f] dark:bg-[#131314] dark:text-[#e3e3e3] dark:hover:bg-[#1f1f20]"
      >
        <svg class="size-5" viewBox="0 0 48 48" aria-hidden="true">
          <path
            fill="#EA4335"
            d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"
          />
          <path
            fill="#4285F4"
            d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"
          />
          <path
            fill="#FBBC05"
            d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"
          />
          <path
            fill="#34A853"
            d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"
          />
        </svg>
        {gettext("Continue with Google")}
      </a>
    </div>
    """
  end

  @doc """
  Renders a container for the Telegram Login Widget.

  The widget script is added by app.js. Nothing is shown if no bot is set.
  """
  attr :id, :string, required: true
  attr :auth_path, :string, required: true
  attr :class, :any, default: "justify-center"

  def telegram_widget(assigns) do
    assigns = assign(assigns, :bot_username, TelegramAuth.bot_username())

    ~H"""
    <div
      :if={@bot_username}
      id={@id}
      class={["flex min-h-10", @class]}
      phx-hook="TelegramLogin"
      phx-update="ignore"
      data-telegram-login={@bot_username}
      data-auth-path={@auth_path}
    >
    </div>
    """
  end

  @doc """
  Renders a container for the Cloudflare Turnstile widget ("I'm not a robot").
  Put it in a form that sends a sign-in link.

  The widget is added by app.js. Nothing is shown if the check is off.
  """
  attr :id, :string, required: true

  def turnstile_widget(assigns) do
    assigns = assign(assigns, :site_key, Turnstile.enabled?() && Turnstile.site_key())

    ~H"""
    <div
      :if={@site_key}
      id={@id}
      class="min-h-[65px]"
      phx-hook="Turnstile"
      phx-update="ignore"
      data-turnstile-sitekey={@site_key}
    >
    </div>
    """
  end

  defp local_mail_adapter? do
    Application.get_env(:octomocto, Octomocto.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
