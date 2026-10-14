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

  slot :header,
    doc: "content between the wordmark and the theme toggle; on a small screen it goes below them"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- The column keeps the footer at the bottom of a short page --%>
    <div class="flex min-h-dvh flex-col">
      <header
        id="site-header"
        class="flex min-h-16 flex-wrap items-center gap-x-8 gap-y-4 px-4 py-3 sm:px-6 lg:px-8"
      >
        <.link :if={@home} id="home-link" navigate={~p"/"} class="group flex items-center gap-4">
          <OctomoctoWeb.PageHTML.octopi class="h-20 shrink-0 drop-shadow-sm" />
          <div class="flex flex-col gap-1">
            <.wordmark class="h-8" />
            <p
              id="slogan"
              class="text-lg font-medium tracking-tight text-octo-navy/70 dark:text-base-content/70"
            >
              Use your heads
            </p>
          </div>
        </.link>
        <.link :if={!@home} id="home-link" navigate={~p"/"} class="group block">
          <.wordmark class="h-6 -translate-y-0.5" />
        </.link>

        <div :if={@header != []} class="order-last w-full xl:order-none xl:w-auto xl:flex-1">
          {render_slot(@header)}
        </div>

        <div class="ml-auto flex items-center gap-4">
          <.theme_toggle />

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
              <div class="min-w-36 rounded-lg border border-base-300 bg-base-100 py-1 shadow-lg">
                <.link
                  id="settings-link"
                  href={~p"/settings"}
                  class="block px-3 py-1.5 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
                >
                  Settings
                </.link>
                <.link
                  id="sign-out-link"
                  href={~p"/signout"}
                  method="delete"
                  class="block px-3 py-1.5 text-base-content/70 transition hover:bg-base-200 hover:text-base-content"
                >
                  Sign out
                </.link>
              </div>
            </div>
          </nav>
        </div>
      </header>

      <main class="flex-1 px-4 pb-6 sm:px-6 lg:px-8">
        <div class={["space-y-4", if(@wide, do: "w-full", else: "mx-auto max-w-2xl")]}>
          {render_slot(@inner_block)}
        </div>
      </main>

      <footer
        id="site-footer"
        class="flex flex-wrap items-center justify-center gap-x-6 gap-y-2 px-4 py-6 text-xs text-base-content/50 sm:px-6 lg:px-8"
      >
        <span>&copy; 2026 Octomocto</span>
        <.link
          id="privacy-link"
          navigate={~p"/privacy"}
          class="transition hover:text-base-content"
        >
          Privacy Policy
        </.link>
        <.link id="terms-link" navigate={~p"/terms"} class="transition hover:text-base-content">
          Terms of Service
        </.link>
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
    <meta property="og:image:alt" content="Octomocto: Use your heads" />
    <meta name="twitter:card" content="summary_large_image" />
    """
  end

  defp page_description(assigns) do
    assigns[:page_description] ||
      "Quick brain games for memory, logic and speed. Play solo or go head to head with friends."
  end

  # The same title as in the browser tab
  defp og_title(nil), do: "Octomocto · Brain Games to Play Solo or with Friends"
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
            {"system", "hero-computer-desktop-micro", "System theme",
             "[[data-theme-mode=system]_&]:text-base-content"},
            {"light", "hero-sun-micro", "Light theme",
             "[[data-theme-mode=light]_&]:text-base-content"},
            {"dark", "hero-moon-micro", "Dark theme", "[[data-theme-mode=dark]_&]:text-base-content"}
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
