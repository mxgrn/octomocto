defmodule OctomoctoWeb.GameNoticesLive do
  @moduledoc """
  The notices on a game page (see `OctomoctoWeb.Notices`). A game page is
  not a LiveView, so the game controller renders this view with
  `live_render/3`, with the `"locale"` of the page in the session.

  The first notice floats over the top of the page, as on the other pages
  (see `OctomoctoWeb.Layouts.app/1`). It takes no space, so that a notice
  does not move the game.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.UserAuth, :mount_current_scope}
  on_mount OctomoctoWeb.GuestName
  on_mount OctomoctoWeb.Notices

  def mount(_params, %{"locale" => locale}, socket) do
    Gettext.put_locale(OctomoctoWeb.Gettext, locale)
    {:ok, socket, layout: false}
  end

  def render(assigns) do
    ~H"""
    <div id="game-notices">
      <div
        :if={@notices != []}
        id="game-notice"
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
          <OctomoctoWeb.Notices.notice notice={hd(@notices)} waiting={length(@notices) - 1} />
        </div>
      </div>
    </div>
    """
  end
end
