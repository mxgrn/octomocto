defmodule OctomoctoWeb.SiteNotifications do
  @moduledoc """
  Assigns the notifications (see `Octomocto.Notifications`) that the bar
  above the header shows, in `:notifications`.

  A LiveView of a game uses it with the game id, and a page without a
  game with nil:

      on_mount {OctomoctoWeb.SiteNotifications, "memory"}

  A controller uses it as a plug, for the site-wide notifications only:

      plug OctomoctoWeb.SiteNotifications

  The page gets all notifications that did not expire. The script in
  `app.js` shows the first one that the user did not close, and keeps the
  closed ones in `localStorage`.
  """

  alias Octomocto.Notifications

  def on_mount(game, _params, _session, socket) do
    {:cont,
     Phoenix.Component.assign(socket, :notifications, Notifications.active_notifications(game))}
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    Plug.Conn.assign(conn, :notifications, Notifications.active_notifications(nil))
  end

  @doc """
  Gives the HTML of the Markdown `text` of a notification, without the
  paragraph around it. Raw HTML in the text is omitted.
  """
  def to_html(text) do
    text
    |> MDEx.to_html!()
    |> String.trim()
    |> String.replace(~r/\A<p>(.*)<\/p>\z/s, "\\1")
  end
end
