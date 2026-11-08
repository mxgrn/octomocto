defmodule OctomoctoWeb.SitemapController do
  use OctomoctoWeb, :controller

  # Only the public pages. The pages of single games are noindex, so they are
  # not in the sitemap.
  defp urls do
    [
      url(~p"/"),
      url(~p"/pt"),
      url(~p"/de"),
      url(~p"/ru"),
      url(~p"/fr"),
      url(~p"/uk"),
      url(~p"/pl"),
      url(~p"/it"),
      url(~p"/es"),
      url(~p"/ja"),
      url(~p"/vi"),
      url(~p"/tr"),
      url(~p"/ar"),
      url(~p"/trains"),
      url(~p"/nimble-mosaic"),
      url(~p"/schulte"),
      url(~p"/memory"),
      url(~p"/pt/memory"),
      url(~p"/de/memory"),
      url(~p"/ru/memory"),
      url(~p"/fr/memory"),
      url(~p"/uk/memory"),
      url(~p"/pl/memory"),
      url(~p"/it/memory"),
      url(~p"/es/memory"),
      url(~p"/ja/memory"),
      url(~p"/vi/memory"),
      url(~p"/tr/memory"),
      url(~p"/ar/memory"),
      url(~p"/set"),
      url(~p"/pt/set"),
      url(~p"/de/set"),
      url(~p"/ru/set"),
      url(~p"/fr/set"),
      url(~p"/uk/set"),
      url(~p"/pl/set"),
      url(~p"/it/set"),
      url(~p"/es/set"),
      url(~p"/ja/set"),
      url(~p"/vi/set"),
      url(~p"/tr/set"),
      url(~p"/ar/set"),
      url(~p"/sudoku"),
      url(~p"/echo"),
      url(~p"/pt/echo"),
      url(~p"/de/echo"),
      url(~p"/ru/echo"),
      url(~p"/fr/echo"),
      url(~p"/uk/echo"),
      url(~p"/pl/echo"),
      url(~p"/it/echo"),
      url(~p"/es/echo"),
      url(~p"/ja/echo"),
      url(~p"/vi/echo"),
      url(~p"/tr/echo"),
      url(~p"/ar/echo"),
      url(~p"/mahjong"),
      url(~p"/overlap"),
      url(~p"/snap"),
      url(~p"/afterglow"),
      url(~p"/graze"),
      url(~p"/privacy"),
      url(~p"/terms"),
      url(~p"/donate"),
      url(~p"/faq"),
      url(~p"/pt/faq"),
      url(~p"/de/faq"),
      url(~p"/ru/faq"),
      url(~p"/fr/faq"),
      url(~p"/uk/faq"),
      url(~p"/pl/faq"),
      url(~p"/it/faq"),
      url(~p"/es/faq"),
      url(~p"/ja/faq"),
      url(~p"/vi/faq"),
      url(~p"/tr/faq"),
      url(~p"/ar/faq")
    ]
  end

  def show(conn, _params) do
    urls = Enum.map_join(urls(), "\n", &"  <url><loc>#{&1}</loc></url>")

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """)
  end
end
