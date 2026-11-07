defmodule OctomoctoWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use OctomoctoWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  attr :guest_name, :string,
    default: nil,
    doc: "the name of a guest (see `OctomoctoWeb.GuestName`), for the menu of a guest"

  attr :guest_public_id, :string,
    default: nil,
    doc: "the public id of the guest (see `Octomocto.Players`), for the link to the profile page"

  attr :home, :boolean,
    default: false,
    doc: "shows the octopi, a larger wordmark and the slogan in the header"

  attr :wide, :boolean,
    default: false,
    doc: "uses the full page width, so that the content lines up with the header"

  attr :game, :boolean,
    default: false,
    doc: "removes the header and the footer, so that the game uses all of the screen"

  attr :welcome, :string,
    default: nil,
    doc: "a message in a bar above the header, which the user can close"

  attr :banners, :list,
    default: [],
    doc: """
    the banners for the bar above the header (see `OctomoctoWeb.SiteBanners`).
    The bar does not show on a game page or below the welcome line.
    """

  attr :languages, :list,
    default: [],
    doc: "the links to the page in each language (see `OctomoctoWeb.Locale.languages/3`)"

  attr :games_played, :integer,
    default: nil,
    doc: """
    the live count of all finished games, for the link to /stats in the footer (see
    `OctomoctoWeb.GamesPlayed`). Without it, the footer reads the count from memory.
    """

  slot :header,
    doc:
      "content between the wordmark and the theme toggle; on a small screen it goes into the menu"

  attr :notices, :list,
    default: [],
    doc: """
    the notices of the user (see `OctomoctoWeb.Notices`). The first one
    floats over the top of the page. A game page shows them with its
    `game_notices` slot.
    """

  slot :game_notices,
    doc: "the notices of a game page (see `OctomoctoWeb.GameNoticesLive`)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- The column keeps the footer at the bottom of a short page --%>
    <div class="flex min-h-dvh flex-col">
      <%!-- Soft brand-colored light behind the page; not behind a game board --%>
      <div
        :if={!@game}
        aria-hidden="true"
        class="pointer-events-none fixed inset-0 -z-10 overflow-hidden"
      >
        <div class="absolute inset-0 bg-gradient-to-b from-octo-mist to-octo-mist/60 dark:from-base-300 dark:via-base-100 dark:to-base-100">
        </div>
        <div class="absolute -top-32 left-1/2 size-[28rem] -translate-x-[85%] rounded-full bg-octo-orange/10 blur-3xl dark:bg-octo-orange-light/10">
        </div>
        <div class="absolute top-24 left-1/2 size-[28rem] -translate-x-[15%] rounded-full bg-octo-indigo/10 blur-3xl dark:bg-octo-indigo-light/10">
        </div>
        <div class="absolute -right-32 -bottom-32 size-[28rem] rounded-full bg-octo-orange/10 blur-3xl dark:bg-octo-orange-light/10">
        </div>
      </div>
      <div
        :if={@welcome}
        id="site-welcome"
        class="flex items-center justify-center gap-3 bg-octo-indigo px-10 py-2 text-center text-sm font-medium text-white relative"
      >
        <span>{@welcome}</span>
        <button
          id="site-welcome-close"
          type="button"
          aria-label={gettext("Close")}
          phx-click={JS.hide(to: "#site-welcome")}
          class="absolute end-2 rounded-full p-1 text-white/70 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <.site_banners
        :if={!@game && !@welcome && @banners != []}
        banners={@banners}
      />
      <header
        :if={!@game}
        id="site-header"
        phx-click-away={@header != [] && close_site_menu()}
        class="relative flex min-h-16 flex-wrap items-center gap-x-4 gap-y-4 sm:gap-x-8 px-4 py-3 sm:px-6 lg:px-8"
      >
        <.link
          :if={@home}
          id="home-link"
          navigate={OctomoctoWeb.Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/")}
          class="group flex items-center gap-3 sm:gap-4"
        >
          <OctomoctoWeb.PageHTML.octopi class="h-[3.6rem] shrink-0 sm:h-[4.5rem] drop-shadow-sm" />
          <div class="flex flex-col gap-1">
            <.wordmark class="h-[1.575rem] sm:h-[1.8rem]" />
            <p
              id="slogan"
              class="text-[0.9rem] font-medium tracking-tight text-octo-navy/70 sm:text-[1.0125rem] dark:text-base-content/70"
            >
              {gettext("Use your heads")}
            </p>
          </div>
        </.link>
        <.link
          :if={!@home}
          id="home-link"
          navigate={OctomoctoWeb.Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/")}
          class="group flex items-center gap-2"
        >
          <OctomoctoWeb.PageHTML.octopi class="h-10 shrink-0 drop-shadow-sm" />
          <.wordmark class="h-6 -translate-y-0.5" />
        </.link>

        <%!--
          Below the lg breakpoint, the header slot and the theme toggle go into a menu
          that opens below the header. On a larger screen, the wrapper has
          `display: contents`, so that its children are items of the header.
        --%>
        <button
          :if={@header != []}
          id="site-menu-button"
          type="button"
          aria-label={gettext("Menu")}
          aria-controls="site-menu"
          aria-expanded="false"
          phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"})}
          class="peer group ms-auto -me-2 flex size-10 items-center justify-center rounded-full text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content active:scale-90 lg:hidden"
        >
          <.icon name="hero-bars-3" class="size-6 group-aria-expanded:hidden" />
          <.icon name="hero-x-mark" class="hidden size-6 group-aria-expanded:block" />
        </button>

        <div
          id="site-menu"
          class={[
            "contents",
            @header != [] &&
              [
                "max-lg:absolute max-lg:inset-x-4 max-lg:top-full max-lg:z-30 max-lg:hidden max-lg:flex-col max-lg:items-center max-lg:gap-4",
                "max-lg:rounded-2xl max-lg:bg-base-100 max-lg:p-4 max-lg:shadow-lg max-lg:ring-1 max-lg:ring-base-content/10",
                "max-lg:peer-aria-expanded:flex"
              ]
          ]}
        >
          <div
            :if={@header != []}
            class="w-full lg:w-auto lg:flex-1"
          >
            {render_slot(@header)}
          </div>

          <div class={[
            "ms-auto flex items-center gap-4",
            @header != [] &&
              "max-lg:ms-0 max-lg:w-full max-lg:justify-between max-lg:border-t max-lg:border-base-content/10 max-lg:pt-4"
          ]}>
            <span :if={@header != []} class="text-sm text-base-content/70 lg:hidden">
              {gettext("Theme")}
            </span>
            <.theme_toggle :if={!@current_scope && !@guest_name} />

            <.account_menu
              :if={!@current_scope && @guest_name}
              id="guest-menu"
              theme_last
              invite_switch={false}
            >
              <:label>
                <.icon name="hero-user-circle" class="size-6" />
                <span class="sr-only">{@guest_name}</span>
              </:label>
              <.link
                :if={@guest_public_id}
                id="profile-link"
                navigate={~p"/players/#{@guest_public_id}"}
                class="block rounded-lg px-3 py-2 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {gettext("Profile")}
              </.link>
              <div id="guest-sign-in" class="space-y-3 px-3 pt-1 pb-3">
                <p class="text-center text-base-content/70">
                  {gettext("Sign in to change your name")}
                </p>
                <OctomoctoWeb.UserSessionHTML.sign_in_bar />
              </div>
            </.account_menu>

            <.account_menu :if={@current_scope} id="user-menu">
              <:label>
                <span class="relative">
                  <img
                    :if={@current_scope.user.avatar_url}
                    src={@current_scope.user.avatar_url}
                    alt=""
                    class="size-8 rounded-full"
                  />
                  <span
                    :if={!@current_scope.user.avatar_url}
                    id="user-menu-initials"
                    aria-hidden="true"
                    class="flex size-8 items-center justify-center rounded-full bg-octo-indigo text-sm font-semibold text-white"
                  >
                    {initials(user_menu_name(@current_scope.user))}
                  </span>
                  <%!-- `app.js` shows and hides it (see `OctomoctoWeb.UnreadNotifications`) --%>
                  <span
                    id="notifications-dot"
                    hidden={@current_scope.unread_notifications == 0}
                    class="absolute -end-0.5 -top-0.5 size-3 rounded-full bg-orange-500 ring-2 ring-base-100"
                  />
                </span>
                <span class="sr-only">{user_menu_name(@current_scope.user)}</span>
              </:label>
              <.link
                id="notifications-link"
                href={~p"/notifications"}
                class="flex items-center justify-between gap-3 rounded-lg px-3 py-2 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {gettext("Notifications")}
                <span
                  id="notifications-count"
                  hidden={@current_scope.unread_notifications == 0}
                  class="min-w-5 rounded-full bg-orange-500 px-1.5 text-center text-xs font-semibold leading-5 text-white tabular-nums"
                >
                  {@current_scope.unread_notifications}
                </span>
              </.link>
              <.link
                id="profile-link"
                navigate={~p"/players/#{@current_scope.user.public_id}"}
                class="block rounded-lg px-3 py-2 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {gettext("Profile")}
              </.link>
              <.link
                id="settings-link"
                href={~p"/settings"}
                class="block rounded-lg px-3 py-2 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {gettext("Settings")}
              </.link>
              <.link
                id="sign-out-link"
                href={~p"/signout"}
                method="delete"
                class="block rounded-lg px-3 py-2 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {gettext("Sign out")}
              </.link>
            </.account_menu>
          </div>
        </div>
      </header>

      {render_slot(@game_notices)}

      <div
        :if={@notices != []}
        id="notice-float"
        phx-mounted={
          JS.transition(
            {"ease-out duration-300", "-translate-y-[150%]", "translate-y-0"},
            time: 300
          )
        }
        phx-remove={
          JS.transition(
            {"ease-in duration-200", "translate-y-0", "-translate-y-[150%]"},
            time: 200
          )
        }
        class="pointer-events-none fixed inset-x-0 top-0 z-50 flex justify-center px-2 pt-2"
      >
        <div class="pointer-events-auto flex min-h-10 max-w-full items-center rounded-full bg-octo-indigo px-4 py-1.5 text-sm text-white shadow-lg shadow-octo-indigo/25">
          <OctomoctoWeb.Notices.notice
            notice={hd(@notices)}
            waiting={length(@notices) - 1}
          />
        </div>
      </div>

      <main class={[
        "flex-1",
        if(@game, do: "px-2 py-2 lg:px-8 lg:py-6", else: "px-4 pb-6 sm:px-6 lg:px-8")
      ]}>
        <div class={["space-y-4", if(@wide, do: "w-full", else: "mx-auto max-w-2xl")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer
        :if={!@game}
        id="site-footer"
        class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 px-4 py-6 text-xs text-base-content/50 sm:px-6 lg:px-8"
      >
        <span>
          &copy; 2026
          <a
            id="author-link"
            href="https://mxgrn.com?utm_source=octomocto"
            class="transition hover:text-base-content"
          >
            Max Gorin
          </a>
        </span>
        <%!-- The count of all finished games (see `Octomocto.Stats.Counter`) --%>
        <.link
          id="games-played"
          navigate={~p"/stats"}
          class="transition hover:text-base-content"
        >
          <span
            id={"games-played-count-#{games_played(@games_played)}"}
            class="games-played-bump font-semibold tabular-nums"
          >
            {delimit(games_played(@games_played))}
          </span>
          {ngettext("game played", "games played", games_played(@games_played))}
        </.link>
        <a
          id="suggest-game-link"
          href="mailto:hi@octomocto.com"
          class="transition hover:text-base-content"
        >
          {gettext("Suggest a game")}
        </a>
        <.link
          id="privacy-link"
          navigate={~p"/privacy"}
          class="transition hover:text-base-content"
        >
          {gettext("Privacy Policy")}
        </.link>
        <.link id="terms-link" navigate={~p"/terms"} class="transition hover:text-base-content">
          {gettext("Terms of Service")}
        </.link>
        <%!--
          The menu opens above the button, because the footer is at the bottom of
          the page. A link goes through /locale/:locale, which remembers the language
          (see `OctomoctoWeb.LocaleRedirect`). Search engines find the pages in the
          other languages through the hreflang links in the head.
        --%>
        <nav
          :if={@languages != []}
          id="language-switcher"
          aria-label={gettext("Language")}
          phx-click-away={close_language_menu()}
          phx-window-keydown={close_language_menu()}
          phx-key="Escape"
          class="relative"
        >
          <button
            id="language-menu-button"
            type="button"
            aria-controls="language-menu"
            aria-expanded="false"
            phx-click={JS.toggle_attribute({"aria-expanded", "true", "false"})}
            class="peer group -my-1 inline-flex items-center gap-1 rounded-full px-2 py-1 transition hover:bg-base-content/5 hover:text-base-content aria-expanded:bg-base-content/5 aria-expanded:text-base-content"
          >
            <.icon name="hero-language" class="size-3.5" />
            {Enum.find(@languages, & &1.current).name}
            <.icon
              name="hero-chevron-up-micro"
              class="size-3.5 transition-transform group-aria-expanded:rotate-180"
            />
          </button>
          <ul
            id="language-menu"
            class={[
              "absolute bottom-full left-1/2 z-30 mb-2 min-w-36 -translate-x-1/2 space-y-0.5 rounded-xl border border-base-300 bg-base-100 p-1.5 text-sm shadow-lg",
              "invisible translate-y-1 opacity-0 transition duration-150",
              "peer-aria-expanded:visible peer-aria-expanded:translate-y-0 peer-aria-expanded:opacity-100"
            ]}
          >
            <li :for={language <- @languages}>
              <span
                :if={language.current}
                lang={language.locale}
                aria-current="true"
                class="flex items-center justify-between gap-4 rounded-lg px-3 py-1.5 font-semibold text-base-content"
              >
                {language.name}
                <.icon name="hero-check-micro" class="size-4 text-octo-indigo" />
              </span>
              <a
                :if={!language.current}
                id={"language-#{language.locale}"}
                href={~p"/locale/#{language.locale}?#{[to: language.path]}"}
                rel="nofollow"
                hreflang={language.locale}
                lang={language.locale}
                class="block rounded-lg px-3 py-1.5 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
              >
                {language.name}
              </a>
            </li>
          </ul>
        </nav>
        <a
          id="donate-link"
          href={OctomoctoWeb.Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/donate")}
          class={[
            "group -my-1 inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-semibold transition",
            "bg-octo-orange/10 text-octo-orange ring-1 ring-octo-orange/30",
            " hover:bg-octo-orange hover:text-white hover:shadow-md hover:shadow-octo-orange/20 active:scale-95",
            "dark:bg-octo-orange-light/10 dark:text-octo-orange-light dark:ring-octo-orange-light/30",
            "dark:hover:bg-octo-orange-light dark:hover:text-base-100"
          ]}
        >
          <.icon name="hero-heart-solid" class="size-3.5 transition group-hover:scale-110" />
          {gettext("Support the author")}
        </a>
      </footer>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  attr :banners, :list, required: true

  # All banners are hidden. The `SiteBanners` hook in `app.js`
  # shows the first one that the user did not close.
  defp site_banners(assigns) do
    ~H"""
    <div id="site-banners" phx-hook="SiteBanners" phx-update="ignore">
      <div
        :for={banner <- @banners}
        id={"site-banner-#{banner.id}"}
        data-banner-id={banner.id}
        hidden
        class="site-banner relative flex items-center justify-center bg-octo-indigo px-10 py-2 text-center text-sm font-medium text-white"
      >
        <span class="[&_a]:font-semibold [&_a]:underline [&_a]:decoration-white/40 [&_a]:underline-offset-2 [&_a]:transition [&_a:hover]:decoration-white">
          {Phoenix.HTML.raw(
            OctomoctoWeb.SiteBanners.to_html(Octomocto.Banners.localized_text(banner))
          )}
        </span>
        <button
          type="button"
          data-close-banner
          aria-label={gettext("Close")}
          class="absolute end-2 rounded-full p-1 text-white/70 transition hover:bg-white/10 hover:text-white active:scale-90"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders the wordmark from `wordmark.svg` inline, so that the eyes in the
  "o" letters can blink when the pointer moves onto the parent `group`.
  Only the orange or only the blue eyes blink. `app.js` picks them at random.
  """
  attr :class, :any, default: nil

  def wordmark(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="-10 12 692 98"
      role="img"
      aria-label="Octomocto"
      class={@class}
    >
      <g
        fill="none"
        stroke="currentColor"
        stroke-width="16"
        stroke-linecap="round"
        stroke-linejoin="round"
      >
        <g class="text-octo-orange dark:text-octo-orange-light">
          <.octo_letters />
        </g>
        <g class="text-octo-indigo dark:text-octo-indigo-light">
          <path d="M292 48V100" />
          <path d="M292 70A22 22 0 0 1 336 70V100" />
          <path d="M336 70A22 22 0 0 1 380 70V100" />
        </g>
        <g class="text-octo-indigo dark:text-octo-indigo-light" transform="translate(408 0)">
          <.octo_letters />
        </g>
      </g>
      <g class="fill-octo-navy dark:fill-white">
        <circle :for={cx <- [33, 245]} class="wordmark-eye-orange" cx={cx} cy="74" r="9" />
        <circle :for={cx <- [427, 639]} class="wordmark-eye-blue" cx={cx} cy="74" r="9" />
      </g>
    </svg>
    """
  end

  defp octo_letters(assigns) do
    ~H"""
    <circle cx="26" cy="74" r="26" />
    <path d="M124.4 55.6A26 26 0 1 0 124.4 92.4" />
    <path d="M166 22V84Q166 100 182 100" />
    <path d="M152 48H184" />
    <circle cx="238" cy="74" r="26" />
    """
  end

  @doc """
  Adds the Open Graph and Twitter tags, so that shared links show a preview
  card.
  """
  attr :title, :string, default: nil, doc: "the page title, without the site name"
  attr :description, :string, required: true
  attr :url, :string, default: nil, doc: "the canonical URL of the page"

  def social_tags(assigns) do
    ~H"""
    <meta property="og:type" content="website" />
    <meta property="og:site_name" content="Octomocto" />
    <meta property="og:title" content={og_title(@title)} />
    <meta property="og:description" content={@description} />
    <meta :if={@url} property="og:url" content={@url} />
    <meta property="og:image" content={url(~p"/images/og.png")} />
    <meta property="og:image:width" content="1200" />
    <meta property="og:image:height" content="630" />
    <meta
      property="og:image:alt"
      content={gettext("Octomocto: Use your heads. Play solo or with friends.")}
    />
    <meta name="twitter:card" content="summary_large_image" />
    """
  end

  defp page_description(assigns) do
    assigns[:page_description] ||
      gettext(
        "Quick brain games for memory, logic and speed. Play solo or go head to head with friends."
      )
  end

  # The same title as in the browser tab
  defp og_title(nil), do: "Octomocto · " <> gettext("Brain Games to Play Solo or with Friends")
  defp og_title(title), do: title

  @doc """
  Adds the Google tag (gtag.js) for Google Analytics.
  """
  def gtag(assigns) do
    ~H"""
    <script async src="https://www.googletagmanager.com/gtag/js?id=G-95LZEBCCVE">
    </script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());

      gtag('config', 'G-95LZEBCCVE');
    </script>
    """
  end

  defp user_menu_name(user), do: user.display_name || user.name || user.email

  # Up to two first letters of the name, for the menu button of a user without an avatar.
  defp initials(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map_join(&String.first/1)
    |> String.upcase()
  end

  attr :id, :string, required: true
  attr :theme_last, :boolean, default: false, doc: "shows the theme toggle below the links"
  attr :invite_switch, :boolean, default: true, doc: "shows the switch of the invite sound"
  slot :label, required: true, doc: "the content of the button"
  slot :inner_block, required: true, doc: "the links below the theme toggle"

  # The menu of the user or the guest in the header. It opens on a click on the
  # button (see app.js), which sets `aria-expanded`. The nav has
  # phx-update="ignore", so that a LiveView update does not close the menu.
  defp account_menu(assigns) do
    ~H"""
    <nav id={@id} phx-update="ignore" data-account-menu class="relative text-sm">
      <button
        id={"#{@id}-button"}
        type="button"
        aria-expanded="false"
        aria-controls={"#{@id}-dropdown"}
        data-account-menu-button
        class="peer flex cursor-pointer items-center gap-2 text-base-content/70 transition hover:text-base-content aria-expanded:text-base-content"
      >
        {render_slot(@label)}
      </button>
      <div
        id={"#{@id}-dropdown"}
        class="invisible absolute end-0 z-30 mt-2 opacity-0 transition peer-aria-expanded:visible peer-aria-expanded:opacity-100"
      >
        <div class="min-w-36 space-y-1 rounded-xl border border-base-300 bg-base-100 p-2 shadow-lg">
          <.theme_row :if={!@theme_last} />
          <.sound_rows
            :if={!@theme_last}
            id={"#{@id}-sounds"}
            invite_switch={@invite_switch}
            class="border-b border-base-300 pb-1"
          />
          {render_slot(@inner_block)}
          <.theme_row :if={@theme_last} class="border-t border-base-300 pt-3" />
          <.sound_rows :if={@theme_last} id={"#{@id}-sounds"} invite_switch={@invite_switch} />
        </div>
      </div>
    </nav>
    """
  end

  attr :class, :string, default: nil

  defp theme_row(assigns) do
    ~H"""
    <div class={["flex items-center justify-between gap-6 px-3 py-2", @class]}>
      <span class="text-base-content/70">{gettext("Theme")}</span>
      <.theme_toggle />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :invite_switch, :boolean, required: true
  attr :class, :string, default: nil

  # The sound switches. They are on by default, and app.js sets their state
  # from the browser storage, so LiveView must not change them.
  defp sound_rows(assigns) do
    ~H"""
    <div id={@id} phx-update="ignore" class={@class}>
      <.sound_switch :if={@invite_switch} kind="invites" label={gettext("Invite sound")} />
      <.sound_switch
        kind="sounds"
        label={if(@invite_switch, do: gettext("All other sounds"), else: gettext("All sounds"))}
      />
    </div>
    """
  end

  attr :kind, :string, required: true
  attr :label, :string, required: true

  defp sound_switch(assigns) do
    ~H"""
    <button
      id={"sound-switch-#{@kind}"}
      type="button"
      role="switch"
      aria-checked="true"
      data-sound-switch={@kind}
      class="group flex w-full cursor-pointer items-center justify-between gap-6 rounded-lg px-3 py-2 text-start text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
    >
      <span class="whitespace-nowrap">{@label}</span>
      <span class="relative h-5 w-9 shrink-0 rounded-full bg-base-content/15 transition-colors duration-200 group-aria-checked:bg-octo-indigo">
        <span class="absolute top-0.5 start-0.5 size-4 rounded-full bg-white shadow-sm transition-[inset-inline-start] duration-200 group-aria-checked:start-4.5"></span>
      </span>
    </button>
    """
  end

  defp close_site_menu do
    JS.set_attribute({"aria-expanded", "false"}, to: "#site-menu-button")
  end

  defp close_language_menu do
    JS.set_attribute({"aria-expanded", "false"}, to: "#language-menu-button")
  end

  @doc """
  Shows a selector for the system, light and dark themes.

  The script in `root.html.heex` keeps the choice and sets `data-theme-mode`
  on the `<html>` element. The slider uses that attribute to find its position.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div
      id="theme-toggle"
      class="relative flex items-center rounded-full bg-base-content/5 p-0.5 ring-1 ring-base-content/10"
    >
      <div class="absolute top-0.5 start-0.5 size-7 rounded-full bg-base-100 shadow-sm ring-1 ring-base-content/10 transition-[inset-inline-start] duration-200 [[data-theme-mode=light]_&]:start-7.5 [[data-theme-mode=dark]_&]:start-14.5">
      </div>

      <button
        :for={
          {mode, icon, label, active_class} <- [
            {"system", "hero-computer-desktop-micro", gettext("System theme"),
             "[[data-theme-mode=system]_&]:text-base-content"},
            {"light", "hero-sun-micro", gettext("Light theme"),
             "[[data-theme-mode=light]_&]:text-base-content"},
            {"dark", "hero-moon-micro", gettext("Dark theme"),
             "[[data-theme-mode=dark]_&]:text-base-content"}
          ]
        }
        id={"theme-#{mode}"}
        type="button"
        title={label}
        aria-label={label}
        data-phx-theme={mode}
        phx-click={JS.dispatch("phx:set-theme")}
        class={[
          "relative flex size-7 cursor-pointer items-center justify-center rounded-full text-base-content/50 transition hover:text-base-content",
          active_class
        ]}
      >
        <.icon name={icon} class="size-4" />
      </button>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ms-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ms-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # The live count of the page, or the count from memory on a page without one
  defp games_played(nil), do: Octomocto.Stats.Counter.get()
  defp games_played(count), do: count

  # A number with a comma between each 3 digits, for example 5,195
  defp delimit(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end
end
