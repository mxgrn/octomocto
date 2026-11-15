defmodule OctomoctoWeb.Visitors do
  @moduledoc """
  The `on_mount` hook that tracks the visitor of each LiveView page (see
  `Octomocto.Visitors`) and assigns the number of visitors in
  `:online_count`, for the footer (see `OctomoctoWeb.Layouts.app/1`). The
  number changes live when a visitor comes or leaves.

  Before the page connects, the page does not track its visitor yet, so the
  number adds the visitor when the count does not have it.

  It must come after `OctomoctoWeb.GuestName`, which assigns `:guest_id`.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Octomocto.Visitors

  def on_mount(:default, _params, _session, socket) do
    key = Visitors.key(user_id(socket.assigns[:current_scope]), socket.assigns[:guest_id])

    if connected?(socket) do
      Visitors.subscribe()
      Visitors.track(self(), key)
    end

    {:cont,
     socket
     |> assign(:online_count, count(key))
     |> attach_hook(:online_count, :handle_info, &handle_info/2)}
  end

  defp handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: "visitors"}, socket),
    do: {:halt, assign(socket, :online_count, Visitors.count())}

  defp handle_info(_message, socket), do: {:cont, socket}

  defp user_id(%{user: %{id: id}}), do: id
  defp user_id(_scope), do: nil

  defp count(nil), do: Visitors.count()

  defp count(key),
    do: if(Visitors.online?(key), do: Visitors.count(), else: Visitors.count() + 1)
end
