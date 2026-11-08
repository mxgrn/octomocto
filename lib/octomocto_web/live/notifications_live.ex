defmodule OctomoctoWeb.NotificationsLive do
  @moduledoc """
  The notifications of the signed-in user, at `/notifications` (see
  `Octomocto.Notifications`). When the page connects, all notifications
  are read and the dot in the header goes away. The ones that were unread
  stay marked on the page until the next visit.

  A follow notification has a "Follow back" button, or "Following" when
  the user already follows the follower.

  A guest sees what the page gives after sign-in, and the sign-in forms.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.{Accounts, Friends, Notifications}
  alias OctomoctoWeb.Locale

  # A guest sees what the page gives after sign-in, and the sign-in forms
  def mount(_params, _session, %{assigns: %{current_scope: nil}} = socket) do
    {:ok, assign(socket, page_title: "Notifications", noindex: true)}
  end

  def mount(_params, _session, socket) do
    user_id = socket.assigns.current_scope.user.id

    # The first render does not mark them, so that the connected render
    # still knows which ones are new
    seen_at =
      if connected?(socket),
        do: Notifications.mark_seen(user_id),
        else: socket.assigns.current_scope.user.notifications_seen_at

    notifications = Notifications.list(user_id)

    # This page reads them all, so the header shows no dot from the first
    # render. The event comes after the count that the hook sends on connect.
    socket =
      socket
      |> update(:current_scope, &%{&1 | unread_notifications: 0})
      |> push_event("unread-notifications", %{count: 0})

    {:ok,
     socket
     |> assign(
       page_title: "Notifications",
       noindex: true,
       seen_at: seen_at,
       followed_ids: MapSet.new(Friends.followed_ids(user_id)),
       empty?: notifications == []
     )
     |> stream(:notifications, notifications)}
  end

  def handle_event("follow_back", %{"id" => id}, socket) do
    me = socket.assigns.current_scope.user.id
    notification = Enum.find(Notifications.list(me), &(to_string(&1.id) == id))

    if notification do
      Friends.follow(me, notification.actor_id)

      {:noreply,
       socket
       |> update(:followed_ids, &MapSet.put(&1, notification.actor_id))
       |> stream_insert(:notifications, notification)}
    else
      {:noreply, socket}
    end
  end

  defp new?(_notification, nil), do: true

  defp new?(notification, seen_at),
    do: DateTime.compare(notification.inserted_at, seen_at) == :gt

  @doc "A short time from now: \"now\", \"5m\", \"3h\", \"2d\", or a date."
  def ago(time, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(now, time)

    cond do
      seconds < 60 -> "now"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      seconds < 7 * 86_400 -> "#{div(seconds, 86_400)}d"
      true -> Locale.short_date(time)
    end
  end

  defp name(user), do: Accounts.public_name(user) || "Someone"
end
