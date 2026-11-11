defmodule OctomoctoWeb.UnreadNotifications do
  @moduledoc """
  Keeps the dot on the menu in the header and the count in the menu
  current (see `Octomocto.Notifications`), for users and guests.

  A user has the count in the scope (see `OctomoctoWeb.UserAuth`). A guest
  has it in the `:guest_unread_notifications` assign. The session of a
  guest keeps the time of the first visit and the time when the guest
  last opened `/notifications`. The guest gets the broadcasts after the
  first visit, and the ones after the last time are unread.

  Use the plug in the browser pipeline, after the plug that assigns
  `:current_scope`, and `mark_guest_seen/2` before `/notifications`.
  Use `on_mount/4` in a `live_session`, after the hook that assigns
  `:current_scope`.

  The page renders the count. The menu of the header does not change
  after the first render (`phx-update="ignore"`), thus the hook sends each
  new count to the browser as the `"unread-notifications"` event, and
  `app.js` changes the dot and the count. It also sends the count when
  the page connects, because a live navigation keeps the old menu.
  """
  import Plug.Conn
  import Phoenix.LiveView

  alias Octomocto.Notifications

  @first_visit_key "notifications_first_visit"
  @seen_key "notifications_seen_at"
  @seen_before_key "notifications_seen_before"

  def init(opts), do: opts

  def call(%{assigns: %{current_scope: %{user: %{}}}} = conn, _opts),
    do: assign(conn, :guest_unread_notifications, 0)

  def call(conn, _opts) do
    conn =
      if get_session(conn, @first_visit_key),
        do: conn,
        else: put_session(conn, @first_visit_key, now())

    assign(conn, :guest_unread_notifications, guest_count(get_session(conn)))
  end

  @doc """
  The plug of `/notifications`: the page reads all broadcasts of a guest.
  The page gets the time before, to mark the new ones (see
  `live_session/1`).
  """
  def mark_guest_seen(%{assigns: %{current_scope: %{user: %{}}}} = conn, _opts), do: conn

  def mark_guest_seen(conn, _opts) do
    conn
    |> assign(:notifications_seen_before, get_session(conn, @seen_key))
    |> put_session(@seen_key, now())
    |> assign(:guest_unread_notifications, 0)
  end

  @doc "The extra session of the `live_session` of `/notifications`."
  def live_session(conn),
    do: %{@seen_before_key => conn.assigns[:notifications_seen_before]}

  @doc "The session keys of the guest, to keep them when the session is renewed."
  def keys, do: [@first_visit_key, @seen_key]

  @doc "The time of the first visit of the guest in the session, or nil."
  def first_visit(session), do: to_time(session[@first_visit_key])

  @doc "The time when the guest last opened `/notifications`, before this visit, or nil."
  def seen_before(session), do: to_time(session[@seen_before_key])

  defp now, do: DateTime.to_unix(DateTime.utc_now(), :microsecond)

  defp to_time(nil), do: nil
  defp to_time(time), do: DateTime.from_unix!(time, :microsecond)

  # The broadcasts after the first visit and after the last visit of the page
  defp guest_count(session) do
    case Enum.reject([session[@first_visit_key], session[@seen_key]], &is_nil/1) do
      [] -> 0
      times -> times |> Enum.max() |> to_time() |> Notifications.guest_unread_count()
    end
  end

  def on_mount(:default, _params, session, socket) do
    socket =
      case socket.assigns.current_scope do
        %{user: %{id: user_id}} ->
          if connected?(socket), do: Notifications.subscribe(user_id)
          Phoenix.Component.assign(socket, :guest_unread_notifications, 0)

        _guest ->
          Phoenix.Component.assign(socket, :guest_unread_notifications, guest_count(session))
      end

    if connected?(socket) do
      Notifications.subscribe_broadcasts()

      {:cont,
       socket
       |> push_count(count(socket))
       |> attach_hook(:unread_notifications, :handle_info, &handle_info(&1, &2, session))}
    else
      {:cont, socket}
    end
  end

  defp handle_info({:unread_notifications, count}, socket, _session),
    do: {:halt, push_count(socket, count)}

  defp handle_info(:broadcast_added, socket, session) do
    count =
      case socket.assigns.current_scope do
        %{user: %{id: user_id}} -> Notifications.unread_count(user_id)
        _guest -> guest_count(session)
      end

    {:halt, push_count(socket, count)}
  end

  defp handle_info(_message, socket, _session), do: {:cont, socket}

  defp count(%{assigns: %{current_scope: %{unread_notifications: count}}}), do: count
  defp count(socket), do: socket.assigns.guest_unread_notifications

  defp push_count(socket, count),
    do: push_event(socket, "unread-notifications", %{count: count})
end
