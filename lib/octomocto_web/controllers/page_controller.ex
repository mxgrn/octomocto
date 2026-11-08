defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  plug OctomoctoWeb.SiteBanners

  def privacy(conn, _params) do
    render(conn, :privacy, page_title: "Privacy Policy")
  end

  def terms(conn, _params) do
    render(conn, :terms, page_title: "Terms of Service")
  end

  # The page has all the languages, as the donate page
  def faq(conn, _params) do
    render(conn, :faq,
      page_title: dgettext("faq", "Frequently asked questions"),
      languages: OctomoctoWeb.Locale.languages(:all, conn.assigns.locale, ~p"/faq"),
      alternate_urls: OctomoctoWeb.Locale.alternate_urls(:all, ~p"/faq")
    )
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
