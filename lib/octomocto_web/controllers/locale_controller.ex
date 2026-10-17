defmodule OctomoctoWeb.LocaleController do
  use OctomoctoWeb, :controller

  @doc """
  Sends a prefixed URL of a page without translations to the English page,
  with the same query. The redirect is temporary, because the page can get
  translations later.
  """
  def english(conn, %{"path" => path}) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, to: "/" <> Enum.join(path, "/") <> query)
  end
end
