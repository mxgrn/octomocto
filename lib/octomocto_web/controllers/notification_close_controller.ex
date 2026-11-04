defmodule OctomoctoWeb.NotificationCloseController do
  @moduledoc """
  Saves that the user or guest closed a notification, for the script of
  the bar of notifications in `app.js`. See
  `Octomocto.Notifications.record_close/3`.
  """
  use OctomoctoWeb, :controller

  alias Octomocto.Notifications
  alias OctomoctoWeb.GuestName

  def create(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {id, ""} ->
        guest = {GuestName.id_from_session(get_session(conn)), conn.assigns[:guest_name]}
        Notifications.record_close(id, conn.assigns.current_scope, guest)
        send_resp(conn, :no_content, "")

      _ ->
        send_resp(conn, :not_found, "")
    end
  end
end
