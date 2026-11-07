defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  plug OctomoctoWeb.SiteNotifications

  def privacy(conn, _params) do
    render(conn, :privacy, page_title: "Privacy Policy")
  end

  def terms(conn, _params) do
    render(conn, :terms, page_title: "Terms of Service")
  end

  # The page has all the languages, so the footer link of each page can go
  # to the page in its language
  def donate(conn, _params) do
    render(conn, :donate,
      page_title: gettext("Support the author"),
      languages: OctomoctoWeb.Locale.languages(:all, conn.assigns.locale, ~p"/donate")
    )
  end
end
