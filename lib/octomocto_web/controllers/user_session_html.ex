defmodule OctomoctoWeb.UserSessionHTML do
  use OctomoctoWeb, :html

  alias Octomocto.Accounts.TelegramAuth

  embed_templates "user_session_html/*"

  @doc """
  Renders the sign-in forms: the Telegram Login Widget and the magic link form.

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

    ~H"""
    <div
      id="sign-in-panel"
      class="space-y-5 rounded-3xl bg-white p-6 shadow-sm ring-1 ring-slate-200 dark:bg-base-200 dark:ring-white/10"
    >
      <.telegram_widget :if={@show_telegram?} id="telegram-sign-in" auth_path={~p"/auth/telegram"} />

      <div
        :if={@show_telegram? && @show_email?}
        class="flex items-center gap-3 text-xs font-medium uppercase tracking-wider text-base-content/40"
      >
        <span class="h-px flex-1 bg-slate-200 dark:bg-white/10"></span>
        or <span class="h-px flex-1 bg-slate-200 dark:bg-white/10"></span>
      </div>

      <.form :if={@show_email?} for={@form} id="sign-in-form" action={~p"/signin"} class="space-y-3">
        <.input
          field={@form[:email]}
          id="sign-in-email"
          type="email"
          placeholder="you@example.com"
          autocomplete="username"
          spellcheck="false"
          readonly={!!@user}
          required
          class="w-full rounded-xl border-0 bg-slate-50 px-4 py-3 ring-1 ring-slate-200 transition placeholder:text-base-content/30 focus:bg-white focus:outline-none dark:bg-base-300 dark:ring-white/10 dark:focus:bg-base-300 focus:ring-2 focus:ring-indigo-500 read-only:text-base-content/60"
        />
        <button
          id="sign-in-submit"
          class="w-full rounded-xl bg-indigo-600 px-4 py-3 font-medium text-white shadow-lg shadow-indigo-600/20 transition hover:-translate-y-0.5 hover:bg-indigo-500 active:translate-y-0"
        >
          Email me a sign-in link
        </button>
      </.form>

      <p :if={local_mail_adapter?()} class="text-center text-xs text-base-content/50">
        Dev: see sent emails in <.link href="/dev/mailbox" class="underline">the mailbox</.link>.
      </p>
    </div>
    """
  end

  @doc """
  Renders a container for the Telegram Login Widget.

  The widget script is added by app.js. Nothing is shown if no bot is set.
  """
  attr :id, :string, required: true
  attr :auth_path, :string, required: true

  def telegram_widget(assigns) do
    assigns = assign(assigns, :bot_username, TelegramAuth.bot_username())

    ~H"""
    <div
      :if={@bot_username}
      id={@id}
      class="flex min-h-10 justify-center"
      data-telegram-login={@bot_username}
      data-auth-path={@auth_path}
    >
    </div>
    """
  end

  defp local_mail_adapter? do
    Application.get_env(:octomocto, Octomocto.Mailer)[:adapter] == Swoosh.Adapters.Local
  end
end
