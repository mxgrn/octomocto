defmodule OctomoctoWeb.Admin.BroadcastFormLive do
  @moduledoc """
  The form to send a notification to all users and guests, or to change
  the text of one. A change does not make it unread again. "Send test"
  sends it only to the admins and keeps the form open. Then "Send to all"
  sends the same notification to all, with the time of now.
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

  # The button that submits the form gives "status": "test" or "sent". A
  # broadcast that was sent to all has only the Save button.
  def handle_event("save", %{"broadcast" => params} = form_params, socket) do
    broadcast = socket.assigns.broadcast
    action = action(broadcast, form_params["status"])

    case save(action, broadcast, params) do
      {:ok, broadcast} ->
        Notifications.translate(broadcast)
        {:noreply, saved(socket, action, broadcast)}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp action(broadcast, status) do
    cond do
      sent?(broadcast) -> :save
      status == "sent" -> :send
      # A submit without a button also sends a test
      true -> :send_test
    end
  end

  defp save(:save, broadcast, params), do: Notifications.update_broadcast(broadcast, params)
  defp save(:send, broadcast, params), do: Notifications.send_broadcast(broadcast, params)

  defp save(:send_test, broadcast, params),
    do: Notifications.send_test_broadcast(broadcast, params)

  # After a test the form stays open, so that the admin can send it to all
  defp saved(socket, :send_test, broadcast) do
    socket
    |> put_flash(:info, "Test sent to the admins")
    |> assign(broadcast: broadcast)
    |> assign_form(Notifications.change_broadcast(broadcast))
  end

  defp saved(socket, action, _broadcast) do
    socket
    |> put_flash(:info, if(action == :send, do: "Notification sent", else: "Notification saved"))
    |> push_navigate(to: ~p"/admin/notifications")
  end

  # The value is an atom from the broadcast, or a string from the params
  defp send_label(audience) when audience in [:users, "users"], do: "Send to users"
  defp send_label(audience) when audience in [:guests, "guests"], do: "Send to guests"
  defp send_label(_audience), do: "Send to all"

  defp sent?(%Broadcast{status: :sent, id: id}), do: not is_nil(id)
  defp sent?(_broadcast), do: false

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
            type="textarea"
            rows="4"
            label="Text (Markdown, in English)"
            placeholder="Try the new [Graze](/graze) game!"
          />

          <.input
            field={@form[:audience]}
            type="select"
            label="Audience"
            options={[
              {"All users and guests", :all},
              {"Users only", :users},
              {"Guests only", :guests}
            ]}
            disabled={sent?(@broadcast)}
          />

          <div class="flex items-center justify-end gap-3 pt-2">
            <.link
              navigate={~p"/admin/notifications"}
              class="rounded-full px-4 py-2 text-sm font-medium text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </.link>
            <%= if sent?(@broadcast) do %>
              <button
                id="save-broadcast"
                type="submit"
                phx-disable-with="Saving..."
                class="rounded-full bg-octo-indigo px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
              >
                Save
              </button>
            <% else %>
              <button
                id="send-test-broadcast"
                type="submit"
                name="status"
                value="test"
                phx-disable-with="Sending..."
                class="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-octo-indigo ring-1 ring-octo-indigo/30 transition hover:bg-octo-indigo/5 hover:ring-octo-indigo/50 active:scale-95 dark:text-octo-indigo-light"
              >
                <.icon name="hero-beaker-micro" class="size-4" /> Send test
              </button>
              <button
                id="save-broadcast"
                type="submit"
                name="status"
                value="sent"
                phx-disable-with="Sending..."
                class="rounded-full bg-octo-indigo px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
              >
                {send_label(@form[:audience].value)}
              </button>
            <% end %>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
