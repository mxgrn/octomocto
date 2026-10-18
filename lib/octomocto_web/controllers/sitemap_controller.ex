defmodule OctomoctoWeb.SitemapController do
  use OctomoctoWeb, :controller

  # Only the public pages. The pages of single games are noindex, so they are
  # not in the sitemap.
  defp urls do
    [
      url(~p"/"),
      url(~p"/trains"),
      url(~p"/schulte"),
      url(~p"/memory"),
      url(~p"/pt/memory"),
      url(~p"/de/memory"),
      url(~p"/ru/memory"),
      url(~p"/fr/memory"),
      url(~p"/uk/memory"),
      url(~p"/set"),
      url(~p"/sudoku"),
      url(~p"/echo"),
      url(~p"/mahjong"),
      url(~p"/astronaut"),
      url(~p"/privacy"),
      url(~p"/terms")
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
