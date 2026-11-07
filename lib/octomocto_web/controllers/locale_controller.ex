defmodule OctomoctoWeb.LocaleController do
  use OctomoctoWeb, :controller

  alias Octomocto.Accounts
  alias OctomoctoWeb.LocaleRedirect

  @doc """
  Sends a prefixed URL of a page without translations to the English page,
  with the same query. The redirect is temporary, because the page can get
  translations later.
  """
  def english(conn, %{"path" => path}) do
    query = if conn.query_string == "", do: "", else: "?" <> conn.query_string
    redirect(conn, to: "/" <> Enum.join(path, "/") <> query)
  end

  @doc """
  Remembers the language that the visitor picked in the footer, also for
  the user, and opens the page `to` (see `OctomoctoWeb.LocaleRedirect`).
  """
  def switch(conn, %{"locale" => locale} = params) do
    to = local_path(params["to"])

    if LocaleRedirect.supported?(locale) do
      if user = conn.assigns.current_scope && conn.assigns.current_scope.user,
        do: Accounts.update_user_preferred_locale(user, locale)

      conn |> LocaleRedirect.put_choice(locale) |> redirect(to: to)
    else
      redirect(conn, to: to)
    end
  end

  # Only a path on this site, so that the link cannot send to a different site
  defp local_path("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/", else: path
  end

  defp local_path(_to), do: "/"
end
