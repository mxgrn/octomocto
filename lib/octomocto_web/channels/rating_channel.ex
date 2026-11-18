defmodule OctomoctoWeb.RatingChannel do
  @moduledoc """
  The star card of the result screen of a game (`octo-rating` in
  `assets/js/rating.js`). The topic is `"rating:<game>"`, with a game id
  of `Octomocto.Ratings.games/0`, and the `"locale"` of the page in the
  join params: its `lang` attribute (see `OctomoctoWeb.Locale.from_html_lang/1`).

  The join reply has `:show` (see `Octomocto.Ratings.show?/2`) and the
  `:texts` of the card in the locale of the page. The user is the signed-in
  user of the socket, never an id from the browser.

  Events:

    * `"vote"` with `"stars"` (1 to 5) saves the vote,
    * `"comment"` with `"text"` adds the comment to a vote of 1 to 4 stars.

  Each replies `:ok` or `:error`.
  """
  use Phoenix.Channel
  use Gettext, backend: OctomoctoWeb.Gettext

  alias Octomocto.Ratings

  @impl true
  def join("rating:" <> game, params, socket) do
    if game in Ratings.games() do
      Gettext.put_locale(
        OctomoctoWeb.Gettext,
        OctomoctoWeb.Locale.from_html_lang(params["locale"])
      )

      show = Ratings.show?(socket.assigns.user_id, game)
      {:ok, %{show: show, texts: texts()}, assign(socket, game: game)}
    else
      {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("vote", %{"stars" => stars}, socket) when is_integer(stars) do
    result(Ratings.vote(socket.assigns.user_id, socket.assigns.game, stars), socket)
  end

  def handle_in("comment", %{"text" => text}, socket) when is_binary(text) do
    result(Ratings.comment(socket.assigns.user_id, socket.assigns.game, text), socket)
  end

  def handle_in(_event, _params, socket), do: {:reply, :error, socket}

  defp result({:ok, _rating}, socket), do: {:reply, :ok, socket}
  defp result({:error, _reason}, socket), do: {:reply, :error, socket}

  defp texts do
    %{
      title: gettext("How do you like this game?"),
      stars: for(n <- 1..5, do: ngettext("%{count} star", "%{count} stars", n)),
      comment_title: gettext("What can we do better?"),
      comment_placeholder: gettext("Optional"),
      send: gettext("Send"),
      thanks: gettext("Thank you!"),
      love: gettext("Thank you! We're happy that you like it!")
    }
  end
end
