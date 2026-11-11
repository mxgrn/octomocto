defmodule OctomoctoWeb.Admin.BroadcastsLive do
  @moduledoc """
  The list of all broadcasts, the newest first: the notifications to all
  users and guests. See `Octomocto.Notifications`.
  """
  use OctomoctoWeb, :live_view

  alias Octomocto.Notifications
  alias OctomoctoWeb.SiteBanners

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Notifications", noindex: true)
     |> stream(:broadcasts, Notifications.list_broadcasts())}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    broadcast = Notifications.get_broadcast!(id)
    {:ok, _broadcast} = Notifications.delete_broadcast(broadcast)

    {:noreply, stream_delete(socket, :broadcasts, broadcast)}
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} games_played={@games_played}>
      <div id="admin-broadcasts" class="flex flex-col gap-6 pt-2 pb-4">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <.link
              id="admin-link"
              navigate={~p"/admin"}
              class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
            >
              <.icon name="hero-chevron-left-micro" class="size-4" /> Admin
            </.link>
            <h1 class="text-2xl font-semibold tracking-tight text-octo-navy dark:text-base-content">
              Notifications
            </h1>
            <p class="mt-1 text-sm text-base-content/60">
              For all users and guests, or only for one of them. A user gets the ones from after the signup, a guest the ones from after the first visit. A test goes only to the admins.
            </p>
          </div>
          <.link
            id="new-broadcast"
            navigate={~p"/admin/notifications/new"}
            class="inline-flex items-center gap-1.5 rounded-full bg-octo-indigo px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New
          </.link>
        </div>

        <ul id="broadcasts" phx-update="stream" class="flex flex-col gap-3">
          <li
            id="broadcasts-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/20 p-8 text-center text-sm text-base-content/60"
          >
            No notifications yet
          </li>
          <li
            :for={{id, broadcast} <- @streams.broadcasts}
            id={id}
            class="flex items-start gap-4 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-base-content/10 dark:bg-base-100 transition"
          >
            <div class="min-w-0 flex-1 space-y-2">
              <div class="text-sm font-medium text-octo-navy dark:text-base-content [&_p+p]:mt-2 [&_a]:font-semibold [&_a]:text-octo-indigo [&_a]:underline [&_a]:decoration-octo-indigo/40 [&_a]:underline-offset-2 [&_a]:transition [&_a:hover]:decoration-octo-indigo dark:[&_a]:text-octo-indigo-light">
                {Phoenix.HTML.raw(SiteBanners.to_html(broadcast.text))}
              </div>
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :if={broadcast.status == :test}
                  id={"status-badge-#{broadcast.id}"}
                  class="inline-flex items-center gap-1 rounded-full bg-amber-500/10 px-2 py-0.5 text-xs font-semibold text-amber-700 ring-1 ring-amber-500/20 dark:text-amber-300"
                >
                  <.icon name="hero-beaker-micro" class="size-3.5" /> Test
                </span>
                <span
                  :if={broadcast.audience != :all}
                  id={"audience-badge-#{broadcast.id}"}
                  class="inline-flex items-center gap-1 rounded-full bg-octo-indigo/10 px-2 py-0.5 text-xs font-semibold text-octo-indigo ring-1 ring-octo-indigo/20 dark:text-octo-indigo-light"
                >
                  <.icon
                    name={
                      if broadcast.audience == :users, do: "hero-user-micro", else: "hero-eye-micro"
                    }
                    class="size-3.5"
                  />
                  {if broadcast.audience == :users, do: "Users only", else: "Guests only"}
                </span>
                <span class="inline-flex items-center gap-1 text-xs text-base-content/70">
                  <.icon name="hero-clock-micro" class="size-3.5" />
                  {if broadcast.status == :test, do: "Sent to the admins", else: "Sent"}
                  {Calendar.strftime(broadcast.inserted_at, "%Y-%m-%d %H:%M")} UTC
                </span>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-1">
              <.link
                id={"edit-broadcast-#{broadcast.id}"}
                navigate={~p"/admin/notifications/#{broadcast}/edit"}
                aria-label="Edit"
                class="rounded-full p-2 text-base-content/60 transition hover:bg-base-content/5 hover:text-octo-indigo"
              >
                <.icon name="hero-pencil-square" class="size-5" />
              </.link>
              <button
                id={"delete-broadcast-#{broadcast.id}"}
                type="button"
                aria-label="Delete"
                phx-click="delete"
                phx-value-id={broadcast.id}
                data-confirm="Delete this notification for all users and guests?"
                class="rounded-full p-2 text-base-content/60 transition hover:bg-error/10 hover:text-error"
              >
                <.icon name="hero-trash" class="size-5" />
              </button>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
