defmodule OctomoctoWeb.NotificationViewController do
  @moduledoc """
  Saves that the user or guest saw (`shown`) or closed (`closed`) a
  notification, for the script of the bar of notifications in `app.js`.
  See `Octomocto.Notifications.record_view/4`.
  """
  use OctomoctoWeb, :controller

  alias Octomocto.Notifications
  alias OctomoctoWeb.GuestName

  @events %{"shown" => :shown, "closed" => :closed}

  def create(conn, %{"id" => id, "event" => event}) do
    with {id, ""} <- Integer.parse(id),
         {:ok, event} <- Map.fetch(@events, event) do
      guest = {GuestName.id_from_session(get_session(conn)), conn.assigns[:guest_name]}
      Notifications.record_view(id, event, conn.assigns.current_scope, guest)
      send_resp(conn, :no_content, "")
    else
      _ -> send_resp(conn, :not_found, "")
    end
  end
end
