defmodule OctomoctoWeb.SiteBanners do
  @moduledoc """
  Assigns the banners (see `Octomocto.Banners`) that the bar
  above the header shows, in `:banners`.

  A LiveView of a game uses it with the game id, and a page without a
  game with nil:

      on_mount {OctomoctoWeb.SiteBanners, "memory"}

  A controller uses it as a plug, for the site-wide banners only:

      plug OctomoctoWeb.SiteBanners

  The page gets all banners that did not expire, without the ones
  that a signed-in user closed. The script in `app.js` shows the first one
  that the user did not close, and keeps the closed ones in `localStorage`.
  It also sends each close to `OctomoctoWeb.BannerCloseController`.
  """

  alias Octomocto.Banners

  def on_mount(game, _params, _session, socket) do
    banners = Banners.active_banners(game, socket.assigns[:current_scope])
    {:cont, Phoenix.Component.assign(socket, :banners, banners)}
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    banners = Banners.active_banners(nil, conn.assigns[:current_scope])
    Plug.Conn.assign(conn, :banners, banners)
  end

  @doc """
  Gives the HTML of the Markdown `text` of a banner, without the
  paragraph around it. Raw HTML in the text is omitted.
  """
  def to_html(text) do
    text
    |> MDEx.to_html!()
    |> String.trim()
    |> String.replace(~r/\A<p>(.*)<\/p>\z/s, "\\1")
  end
end
