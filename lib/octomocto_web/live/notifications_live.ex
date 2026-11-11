defmodule OctomoctoWeb.NotificationsLive do
  @moduledoc """
  The notifications of the user or the guest, at `/notifications` (see
  `Octomocto.Notifications`). When the page opens, all notifications are
  read and the dot in the header goes away. The ones that were unread stay
  marked on the page until the next visit.

  A follow notification has a "Follow back" button, or "Following" when
  the user already follows the follower.

  A guest gets only the broadcasts, and a link to sign in. The session of
  the guest keeps the read state (see `OctomoctoWeb.UnreadNotifications`).
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.{Accounts, Friends, Notifications}
  alias Octomocto.Notifications.{Broadcast, Notification}
  alias OctomoctoWeb.{Locale, SiteBanners, UnreadNotifications}

  # The plug of the route marked the broadcasts read (see
  # `UnreadNotifications.mark_guest_seen/2`)
  def mount(_params, session, %{assigns: %{current_scope: nil}} = socket) do
    notifications =
      case UnreadNotifications.first_visit(session) do
        nil -> []
        first_visit -> Notifications.guest_list(first_visit)
      end

    {:ok,
     socket
     |> assign(
       page_title: "Notifications",
       noindex: true,
       seen_at: UnreadNotifications.seen_before(session),
       followed_ids: MapSet.new(),
       empty?: notifications == []
     )
     |> stream_notifications(notifications)}
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
     |> stream_notifications(notifications)}
  end

  defp stream_notifications(socket, notifications) do
    socket
    |> stream_configure(:notifications, dom_id: &dom_id/1)
    |> stream(:notifications, notifications)
  end

  defp dom_id(%Notification{id: id}), do: "notifications-follow-#{id}"
  defp dom_id(%Broadcast{id: id}), do: "notifications-broadcast-#{id}"

  def handle_event("follow_back", %{"id" => id}, socket) do
    me = socket.assigns.current_scope.user.id

    notification =
      Enum.find(Notifications.list(me), &(match?(%Notification{}, &1) and to_string(&1.id) == id))

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

  defp broadcast_html(broadcast), do: Phoenix.HTML.raw(SiteBanners.to_html(broadcast.text))
end
