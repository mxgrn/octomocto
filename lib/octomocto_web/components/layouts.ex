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

  attr :home, :boolean,
    default: false,
    doc: "shows the octopi, a larger wordmark and the slogan in the header"

  attr :wide, :boolean,
    default: false,
    doc: "uses the full page width, so that the content lines up with the header"

  attr :game, :boolean,
    default: false,
    doc: "removes the header and the footer, so that the game uses all of the screen"

  attr :banner, :string,
    default: nil,
    doc: "a message in a bar above the header, which the user can close"

  attr :languages, :list,
    default: [],
    doc: "the links to the page in each language (see `OctomoctoWeb.Locale.languages/3`)"

  slot :header,
    doc:
      "content between the wordmark and the theme toggle; on a small screen it goes into the menu"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- The column keeps the footer at the bottom of a short page --%>
    <div class="flex min-h-dvh flex-col">
      <div
        :if={@banner}
        id="site-banner"
        class="flex items-center justify-center gap-3 bg-octo-indigo px-10 py-2 text-center text-sm font-medium text-white relative"
      >
        <span>{@banner}</span>
        <button
          id="site-banner-close"
          type="button"
          aria-label={gettext("Close")}
          phx-click={JS.hide(to: "#site-banner")}
          class="absolute right-2 rounded-full p-1 text-white/70 transition hover:bg-white/10 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-4" />
        </button>
      </div>
      <header
        :if={!@game}
        id="site-header"
        phx-click-away={@header != [] && close_site_menu()}
        class="relative flex min-h-16 flex-wrap items-center gap-x-4 gap-y-4 sm:gap-x-8 px-4 py-3 sm:px-6 lg:px-8"
      >
        <.link
          :if={@home}
          id="home-link"
          navigate={~p"/"}
          class="group flex items-center gap-3 sm:gap-4"
        >
          <OctomoctoWeb.PageHTML.octopi class="h-16 shrink-0 sm:h-20 drop-shadow-sm" />
          <div class="flex flex-col gap-1">
            <.wordmark class="h-7 sm:h-8" />
            <p
              id="slogan"
              class="text-base font-medium tracking-tight text-octo-navy/70 sm:text-lg dark:text-base-content/70"
            >
              {gettext("Use your heads")}
            </p>
          </div>
        </.link>
        <.link :if={!@home} id="home-link" navigate={~p"/"} class="group block">
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
          class="peer group ml-auto -mr-2 flex size-10 items-center justify-center rounded-full text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content active:scale-90 lg:hidden"
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
            "ml-auto flex items-center gap-4",
            @header != [] &&
              "max-lg:ml-0 max-lg:w-full max-lg:justify-between max-lg:border-t max-lg:border-base-content/10 max-lg:pt-4"
          ]}>
            <span :if={@header != []} class="text-sm text-base-content/70 lg:hidden">
              {gettext("Theme")}
            </span>
            <.theme_toggle :if={!@current_scope} />

            <nav :if={@current_scope} id="user-menu" class="group relative text-sm">
              <button
                id="user-menu-button"
                type="button"
                class="flex cursor-default items-center gap-2 text-base-content/70 transition group-hover:text-base-content group-focus-within:text-base-content"
              >
                <img
                  :if={@current_scope.user.avatar_url}
                  src={@current_scope.user.avatar_url}
                  alt=""
                  class="size-6 rounded-full"
                />
                {@current_scope.user.display_name || @current_scope.user.name ||
                  @current_scope.user.email}
              </button>
              <%!-- pt-2 instead of a margin keeps the hover area unbroken between button and menu --%>
              <div
                id="user-menu-dropdown"
                class="invisible absolute right-0 z-10 pt-2 opacity-0 transition group-hover:visible group-hover:opacity-100 group-focus-within:visible group-focus-within:opacity-100"
              >
                <div class="min-w-36 space-y-1 rounded-xl border border-base-300 bg-base-100 p-2 shadow-lg">
                  <div class="flex items-center justify-between gap-6 px-3 py-2">
                    <span class="text-base-content/70">{gettext("Theme")}</span>
                    <.theme_toggle />
                  </div>
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
                </div>
              </div>
            </nav>
          </div>
        </div>
      </header>

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
        <a
          id="patreon-link"
          href="https://patreon.com/mxgrn"
          class={[
            "group -my-1 inline-flex items-center gap-1.5 rounded-full px-3 py-1 font-semibold transition",
            "bg-octo-orange/10 text-octo-orange ring-1 ring-octo-orange/30",
            "hover:-translate-y-0.5 hover:bg-octo-orange hover:text-white hover:shadow-md hover:shadow-octo-orange/20 active:scale-95",
            "dark:bg-octo-orange-light/10 dark:text-octo-orange-light dark:ring-octo-orange-light/30",
            "dark:hover:bg-octo-orange-light dark:hover:text-base-100"
          ]}
        >
          <.icon name="hero-heart-solid" class="size-3.5 transition group-hover:scale-110" />
          {gettext("Feed Octo & Mocto")}
        </a>
        <nav
          :if={@languages != []}
          id="language-switcher"
          aria-label={gettext("Language")}
          class="flex items-center gap-1"
        >
          <.icon name="hero-language" class="size-3.5" />
          <%= for language <- @languages do %>
            <span
              :if={language.current}
              class="rounded-full px-2 py-0.5 font-semibold text-base-content/70"
            >
              {language.name}
            </span>
            <a
              :if={!language.current}
              id={"language-#{language.locale}"}
              href={language.path}
              hreflang={language.locale}
              class="rounded-full px-2 py-0.5 transition hover:bg-base-content/5 hover:text-base-content"
            >
              {language.name}
            </a>
          <% end %>
        </nav>
      </footer>
    </div>

    <.flash_group flash={@flash} />
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
        <g class="text-octo-navy dark:text-white">
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
  defp og_title(title), do: "#{title} · Octomocto"

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

  defp close_site_menu do
    JS.set_attribute({"aria-expanded", "false"}, to: "#site-menu-button")
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
      <div class="absolute top-0.5 left-0.5 size-7 rounded-full bg-base-100 shadow-sm ring-1 ring-base-content/10 transition-[left] duration-200 [[data-theme-mode=light]_&]:left-7.5 [[data-theme-mode=dark]_&]:left-14.5">
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
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
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
