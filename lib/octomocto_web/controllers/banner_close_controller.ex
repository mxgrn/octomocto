defmodule OctomoctoWeb.BannerCloseController do
  @moduledoc """
  Saves that the user or guest closed a banner, for the script of
  the bar of banners in `app.js`. See
  `Octomocto.Banners.record_close/3`.
  """
  use OctomoctoWeb, :controller

  alias Octomocto.Banners
  alias OctomoctoWeb.GuestName

  def create(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {id, ""} ->
        guest = {GuestName.id_from_session(get_session(conn)), conn.assigns[:guest_name]}
        Banners.record_close(id, conn.assigns.current_scope, guest)
        send_resp(conn, :no_content, "")

      _ ->
        send_resp(conn, :not_found, "")
    end
  end
end
