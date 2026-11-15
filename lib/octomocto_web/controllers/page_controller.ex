defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  plug OctomoctoWeb.SiteBanners

  def privacy(conn, _params) do
    render(conn, :privacy,
      page_title: "Privacy Policy",
      page_description:
        "What data Octomocto collects when you play, why it uses the data, how long it keeps it, and your rights."
    )
  end

  def terms(conn, _params) do
    render(conn, :terms,
      page_title: "Terms of Service",
      page_description:
        "The rules for using Octomocto: your account, rules of conduct, our content, and the limits of our liability."
    )
  end

  # The page has all the languages, as the donate page
  def faq(conn, _params) do
    render(conn, :faq,
      page_title: dgettext("faq", "Frequently asked questions"),
      page_description:
        dgettext(
          "faq",
          "Answers about Octomocto: is it free, how to play with a friend, public and private games, why to sign in, and how friends and follows work."
        ),
      languages: OctomoctoWeb.Locale.languages(:all, conn.assigns.locale, ~p"/faq"),
      # A URL with a query is a duplicate of the page, so it has no hreflang links
      alternate_urls:
        if(conn.query_string == "",
          do: OctomoctoWeb.Locale.alternate_urls(:all, ~p"/faq"),
          else: []
        )
    )
  end

  # The page has all the languages, so the footer link of each page can go
  # to the page in its language
  def donate(conn, _params) do
    render(conn, :donate,
      page_title: gettext("Support the author"),
      page_description:
        gettext(
          "Octomocto is free and has no ads. Support the indie developer on Patreon to pay for the servers and new games."
        ),
      languages: OctomoctoWeb.Locale.languages(:all, conn.assigns.locale, ~p"/donate")
    )
  end
end
