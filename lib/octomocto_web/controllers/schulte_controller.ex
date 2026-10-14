defmodule OctomoctoWeb.SchulteController do
  use OctomoctoWeb, :controller

  alias Octomocto.Schulte.Store
  alias OctomoctoWeb.SchulteLive

  plug :put_seo

  def show(conn, %{"id" => id}) do
    if state = Store.read(id) do
      render(conn, :show,
        id: id,
        settings_path: SchulteLive.settings_path(state),
        user_token: user_token(conn.assigns.current_scope),
        noindex: true
      )
    else
      conn
      |> put_flash(:error, "This game does not exist (any more). Start a new one.")
      |> redirect(to: ~p"/schulte")
    end
  end

  defp put_seo(conn, _opts), do: merge_assigns(conn, SchulteLive.seo())

  defp user_token(%{user: user}), do: OctomoctoWeb.UserSocket.user_token(user.id)
  defp user_token(nil), do: nil
end
