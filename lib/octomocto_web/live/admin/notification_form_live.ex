defmodule OctomoctoWeb.Admin.NotificationFormLive do
  @moduledoc "The form to add a notification or to change one."
  use OctomoctoWeb, :live_view

  alias Octomocto.Notifications
  alias Octomocto.Notifications.Notification
  alias OctomoctoWeb.Admin.NotificationsLive
  alias OctomoctoWeb.HomeLive

  def mount(params, _session, socket) do
    notification = notification(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(
       page_title: page_title(socket.assigns.live_action),
       noindex: true,
       notification: notification,
       game_options: [
         {NotificationsLive.pages_name(nil), ""}
         | Enum.map(HomeLive.games(), &{&1.name, &1.id})
       ]
     )
     |> assign_form(Notifications.change_notification(notification))}
  end

  # A new notification expires in a week, at the start of the hour
  defp notification(:new, _params) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(7, :day)
      |> Map.merge(%{minute: 0, second: 0, microsecond: {0, 0}})

    %Notification{expires_at: expires_at}
  end

  defp notification(:edit, %{"id" => id}), do: Notifications.get_notification!(id)

  defp page_title(:new), do: "New notification"
  defp page_title(:edit), do: "Edit notification"

  def handle_event("validate", %{"notification" => params}, socket) do
    changeset = Notifications.change_notification(socket.assigns.notification, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"notification" => params}, socket) do
    case save(socket.assigns.live_action, socket.assigns.notification, params) do
      {:ok, _notification} ->
        {:noreply,
         socket
         |> put_flash(:info, "Notification saved")
         |> push_navigate(to: ~p"/admin/notifications")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(:new, _notification, params), do: Notifications.create_notification(params)

  defp save(:edit, notification, params),
    do: Notifications.update_notification(notification, params)

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="admin-notification" class="flex flex-col gap-6 pt-2 pb-4">
        <div>
          <.link
            id="notifications-link"
            navigate={~p"/admin/notifications"}
            class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
          >
            <.icon name="hero-chevron-left-micro" class="size-4" /> Notifications
          </.link>
          <h1 class="text-2xl font-semibold tracking-tight text-octo-navy dark:text-base-content">
            {@page_title}
          </h1>
        </div>

        <.form
          for={@form}
          id="notification-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10 sm:p-6"
        >
          <.input
            field={@form[:text]}
            type="text"
            label="Text (Markdown, on one line)"
            placeholder="Try the new [Overlap](/overlap) game!"
            autocomplete="off"
          />
          <.input field={@form[:game]} type="select" label="Pages" options={@game_options} />
          <.input field={@form[:expires_at]} type="datetime-local" label="Expires at (UTC)" />

          <div class="flex items-center justify-end gap-3 pt-2">
            <.link
              navigate={~p"/admin/notifications"}
              class="rounded-full px-4 py-2 text-sm font-medium text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </.link>
            <button
              id="save-notification"
              type="submit"
              phx-disable-with="Saving..."
              class="rounded-full bg-octo-indigo px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:-translate-y-0.5 hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
