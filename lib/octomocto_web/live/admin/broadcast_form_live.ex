defmodule OctomoctoWeb.Admin.BroadcastFormLive do
  @moduledoc """
  The form to send a notification to all users and guests, or to change
  the text of one. A change does not make it unread again.
  """
  use OctomoctoWeb, :live_view

  alias Octomocto.Notifications
  alias Octomocto.Notifications.Broadcast

  def mount(params, _session, socket) do
    broadcast = broadcast(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(
       page_title: page_title(socket.assigns.live_action),
       noindex: true,
       broadcast: broadcast
     )
     |> assign_form(Notifications.change_broadcast(broadcast))}
  end

  defp broadcast(:new, _params), do: %Broadcast{}
  defp broadcast(:edit, %{"id" => id}), do: Notifications.get_broadcast!(id)

  defp page_title(:new), do: "New notification"
  defp page_title(:edit), do: "Edit notification"

  def handle_event("validate", %{"broadcast" => params}, socket) do
    changeset = Notifications.change_broadcast(socket.assigns.broadcast, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"broadcast" => params}, socket) do
    case save(socket.assigns.live_action, socket.assigns.broadcast, params) do
      {:ok, broadcast} ->
        Notifications.translate(broadcast)

        {:noreply,
         socket
         |> put_flash(:info, saved_message(socket.assigns.live_action))
         |> push_navigate(to: ~p"/admin/notifications")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(:new, _broadcast, params), do: Notifications.create_broadcast(params)
  defp save(:edit, broadcast, params), do: Notifications.update_broadcast(broadcast, params)

  defp saved_message(:new), do: "Notification sent"
  defp saved_message(:edit), do: "Notification saved"

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} games_played={@games_played}>
      <div id="admin-broadcast" class="flex flex-col gap-6 pt-2 pb-4">
        <div>
          <.link
            id="broadcasts-link"
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
          id="broadcast-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 rounded-2xl bg-white p-5 shadow-sm ring-1 ring-base-content/10 dark:bg-base-100 sm:p-6"
        >
          <.input
            field={@form[:text]}
            type="text"
            label="Text (Markdown, on one line, in English)"
            placeholder="Try the new [Graze](/graze) game!"
            autocomplete="off"
          />

          <div class="flex items-center justify-end gap-3 pt-2">
            <.link
              navigate={~p"/admin/notifications"}
              class="rounded-full px-4 py-2 text-sm font-medium text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </.link>
            <button
              id="save-broadcast"
              type="submit"
              phx-disable-with="Saving..."
              class="rounded-full bg-octo-indigo px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
            >
              {if @live_action == :new, do: "Send to all", else: "Save"}
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
