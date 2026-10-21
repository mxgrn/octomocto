defmodule OctomoctoWeb.Admin.DashboardLive do
  @moduledoc "The start page of the admins, with links to the admin pages."
  use OctomoctoWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Admin", noindex: true)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin" class="flex flex-col gap-6 pt-2 pb-4">
        <h1 class="text-2xl font-semibold tracking-tight text-octo-navy dark:text-base-content">
          Admin
        </h1>

        <.link
          id="admin-notifications-link"
          navigate={~p"/admin/notifications"}
          class="group flex items-center gap-4 rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10 transition hover:-translate-y-0.5 hover:shadow-md hover:ring-octo-indigo/40"
        >
          <span class="flex size-11 shrink-0 items-center justify-center rounded-xl bg-octo-indigo/10 text-octo-indigo dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light">
            <.icon name="hero-megaphone" class="size-6" />
          </span>
          <span class="flex-1">
            <span class="block font-semibold text-octo-navy dark:text-base-content">
              Notifications
            </span>
            <span class="block text-sm text-base-content/60">
              Messages in a bar above the header, for all pages or for one game
            </span>
          </span>
          <.icon
            name="hero-chevron-right"
            class="size-5 text-base-content/40 transition group-hover:translate-x-0.5 group-hover:text-octo-indigo"
          />
        </.link>
      </div>
    </Layouts.app>
    """
  end
end
