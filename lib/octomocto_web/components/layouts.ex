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

  attr :home, :boolean, default: false, doc: "shows a larger wordmark in the header"

  attr :wide, :boolean,
    default: false,
    doc: "uses the full page width, so that the content lines up with the header"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header id="site-header" class="flex h-16 items-center px-4 sm:px-6 lg:px-8">
      <.link id="home-link" navigate={~p"/"} class="group block">
        <.wordmark class={if(@home, do: "h-8", else: "h-6 -translate-y-0.5")} />
      </.link>

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
            {@current_scope.user.name || @current_scope.user.email}
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

    <main class="px-4 pb-6 sm:px-6 lg:px-8">
      <div class={["space-y-4", if(@wide, do: "w-full", else: "mx-auto max-w-2xl")]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Renders the wordmark from `wordmark.svg` inline, so that the eyes in the
  "o" letters can blink when the pointer moves onto the parent `group`.
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
        <circle :for={cx <- [33, 245]} class="wordmark-eye" cx={cx} cy="74" r="9" />
        <circle
          :for={cx <- [427, 639]}
          class="wordmark-eye wordmark-eye-late"
          cx={cx}
          cy="74"
          r="9"
        />
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
