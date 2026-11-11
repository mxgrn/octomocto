defmodule OctomoctoWeb.ProfileController do
  @moduledoc """
  The Profile item of the menu of a guest without results. A guest with
  results, and a user, go to their profile page. A guest without results
  has no profile page yet (see `Octomocto.Players`), thus sees the
  sign-in forms.
  """
  use OctomoctoWeb, :controller

  plug OctomoctoWeb.SiteBanners

  def show(%{assigns: %{current_scope: %{user: user}}} = conn, _params),
    do: redirect(conn, to: ~p"/players/#{profile_id(user)}")

  def show(%{assigns: %{guest_public_id: public_id}} = conn, _params) when public_id != nil,
    do: redirect(conn, to: ~p"/players/#{public_id}")

  def show(conn, _params), do: render(conn, :guest, page_title: "Profile", noindex: true)

  defp profile_id(user), do: OctomoctoWeb.CoreComponents.profile_id(user)
end
