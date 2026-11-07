defmodule OctomoctoWeb.UnreadNotifications do
  @moduledoc """
  The `on_mount` hook that keeps the dot on the avatar in the header and
  the count in the menu current (see `Octomocto.Notifications`). It runs
  after the hook that assigns `:current_scope`.

  The page renders the count from the scope. The menu of the header does
  not change after the first render (`phx-update="ignore"`), thus the
  hook sends each new count to the browser as the
  `"unread-notifications"` event, and `app.js` changes the dot and the
  count. It also sends the count when the page connects, because a live
  navigation keeps the old menu.
  """
  import Phoenix.LiveView

  alias Octomocto.Notifications

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns.current_scope do
      %{user: %{id: user_id}, unread_notifications: count} ->
        if connected?(socket) do
          Notifications.subscribe(user_id)

          {:cont,
           socket
           |> push_count(count)
           |> attach_hook(:unread_notifications, :handle_info, &handle_info/2)}
        else
          {:cont, socket}
        end

      _ ->
        {:cont, socket}
    end
  end

  defp handle_info({:unread_notifications, count}, socket),
    do: {:halt, push_count(socket, count)}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp push_count(socket, count),
    do: push_event(socket, "unread-notifications", %{count: count})
end
