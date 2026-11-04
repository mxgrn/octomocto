defmodule OctomoctoWeb.SchulteRedirectController do
  @moduledoc """
  The old URLs of Nimble Mosaic, from the time when its name was "Schulte".
  They go to the new URLs with a temporary redirect (302), and the page
  tells the player about the new name. Browsers do not keep a 302, so
  "/schulte" can become the page of the classic Schulte tables later.
  """
  use OctomoctoWeb, :controller

  @notice "Schulte is now called Nimble Mosaic. Classic Schulte tables are coming soon."

  def index(conn, _params), do: go(conn, ~p"/nimble-mosaic")

  def show(conn, %{"id" => id}), do: go(conn, ~p"/nimble-mosaic/#{id}")

  def stats(conn, _params), do: go(conn, ~p"/stats/nimble-mosaic")

  # Keeps the query, for example the settings of a shared settings link
  defp go(conn, path) do
    path = if conn.query_string == "", do: path, else: path <> "?" <> conn.query_string

    conn
    |> put_flash(:info, @notice)
    |> redirect(to: path)
  end
end
