defmodule OctomoctoWeb.Admin.NotificationsLive do
  @moduledoc """
  The list of all notifications, in the order that pages show them. See
  `Octomocto.Notifications`.
  """
  use OctomoctoWeb, :live_view

  alias Octomocto.Notifications
  alias OctomoctoWeb.{HomeLive, SiteNotifications}

  def mount(_params, _session, socket) do
    notifications = Notifications.list_notifications()

    {:ok,
     socket
     |> assign(page_title: "Notifications", noindex: true, now: DateTime.utc_now())
     |> assign(:empty?, notifications == [])
     |> stream(:notifications, notifications)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    notification = Notifications.get_notification!(id)
    {:ok, _notification} = Notifications.delete_notification(notification)

    {:noreply, stream_delete(socket, :notifications, notification)}
  end

  @doc "The name of the pages that show a notification of the `game`."
  def pages_name(nil), do: "All pages"
  def pages_name(game), do: Enum.find(HomeLive.games(), &(&1.id == game)).name

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-notifications" class="flex flex-col gap-6 pt-2 pb-4">
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
              A page shows one at a time, in this order. The next one shows after the user closes the previous one, or after it expires.
            </p>
          </div>
          <.link
            id="new-notification"
            navigate={~p"/admin/notifications/new"}
            class="inline-flex items-center gap-1.5 rounded-full bg-octo-indigo px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
          >
            <.icon name="hero-plus-micro" class="size-4" /> New
          </.link>
        </div>

        <ul id="notifications" phx-update="stream" class="flex flex-col gap-3">
          <li
            id="notifications-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/20 p-8 text-center text-sm text-base-content/60"
          >
            No notifications yet
          </li>
          <li
            :for={{id, notification} <- @streams.notifications}
            id={id}
            class={[
              "flex items-start gap-4 rounded-2xl bg-base-100 p-4 shadow-sm ring-1 ring-base-content/10 transition",
              expired?(notification, @now) && "opacity-60"
            ]}
          >
            <div class="min-w-0 flex-1 space-y-2">
              <p class="truncate text-sm font-medium text-octo-navy dark:text-base-content [&_a]:font-semibold [&_a]:text-octo-indigo [&_a]:underline [&_a]:decoration-octo-indigo/40 [&_a]:underline-offset-2 [&_a]:transition [&_a:hover]:decoration-octo-indigo dark:[&_a]:text-octo-indigo-light">
                {Phoenix.HTML.raw(SiteNotifications.to_html(notification.text))}
              </p>
              <div class="flex flex-wrap items-center gap-2 text-xs">
                <span class="rounded-full bg-octo-indigo/10 px-2 py-0.5 font-medium text-octo-indigo dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light">
                  {pages_name(notification.game)}
                </span>
                <span class={[
                  "inline-flex items-center gap-1",
                  if(expired?(notification, @now),
                    do: "text-base-content/60",
                    else: "text-base-content/70"
                  )
                ]}>
                  <.icon name="hero-clock-micro" class="size-3.5" />
                  {if expired?(notification, @now), do: "Expired", else: "Expires"}
                  {Calendar.strftime(notification.expires_at, "%Y-%m-%d %H:%M")} UTC
                </span>
              </div>
            </div>
            <div class="flex shrink-0 items-center gap-1">
              <.link
                id={"edit-notification-#{notification.id}"}
                navigate={~p"/admin/notifications/#{notification}/edit"}
                aria-label="Edit"
                class="rounded-full p-2 text-base-content/60 transition hover:bg-base-content/5 hover:text-octo-indigo"
              >
                <.icon name="hero-pencil-square" class="size-5" />
              </.link>
              <button
                id={"delete-notification-#{notification.id}"}
                type="button"
                aria-label="Delete"
                phx-click="delete"
                phx-value-id={notification.id}
                data-confirm="Delete this notification?"
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

  defp expired?(notification, now), do: DateTime.compare(notification.expires_at, now) != :gt
end
