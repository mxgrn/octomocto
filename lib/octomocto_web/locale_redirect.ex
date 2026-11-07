defmodule OctomoctoWeb.LocaleRedirect do
  @moduledoc """
  Sends a visitor from an English page (a URL without a language prefix)
  to the same page in the language of the visitor, for example from
  `/memory` to `/pt/memory`.

  The language of the visitor is the first of:

    1. the language that the user picked in the footer
       (`preferred_locale` of the user),
    2. the language that the visitor picked in the footer (in the
       session, see `put_choice/2`),
    3. the first language of the browser, when the site has it,
    4. English.

  When the language is English, or when the page has no translation in
  the language, the visitor stays on the English page. The router tells
  if the page has a translation: a page without one goes to
  `OctomoctoWeb.LocaleController` (see `localized_path/3`). A URL with a
  prefix never goes to a different language, so a shared link always
  opens in its language.

  As a plug, it redirects the first request. As an `on_mount` hook, it
  redirects a live navigation to an English page.
  """
  import Plug.Conn

  alias OctomoctoWeb.GuestName
  alias OctomoctoWeb.Locale

  @session_key "locale"

  # Search engines must see the English pages
  @bot ~r/bot|crawl|spider|slurp|facebookexternalhit|preview/i

  @doc "The session key of the language that the visitor picked."
  def session_key, do: @session_key

  @doc "True when the site has pages in the language, English included."
  def supported?(locale), do: locale in ["en" | Locale.other_locales()]

  @doc "Remembers the language that the visitor picked in the footer."
  def put_choice(conn, locale), do: put_session(conn, @session_key, locale)

  @doc "The language of the visitor (see the module docs)."
  def locale(user, session) do
    cond do
      user && supported?(user.preferred_locale) -> user.preferred_locale
      supported?(session[@session_key]) -> session[@session_key]
      true -> browser_locale(GuestName.locale_from_session(session))
    end
  end

  # "pt-BR" is "pt", "es-ES" is "es"
  defp browser_locale(nil), do: "en"

  defp browser_locale(tag) do
    language = tag |> String.split("-") |> hd() |> String.downcase()
    if supported?(language), do: language, else: "en"
  end

  @doc """
  The path of the page in the language, with the query, or nil when the
  page has no translation in the language. The `path` is the path of the
  English page.
  """
  def localized_path("en", _path, _query, _host), do: nil

  def localized_path(locale, path, query, host) do
    localized = Locale.path(locale, path)

    case Phoenix.Router.route_info(OctomoctoWeb.Router, "GET", localized, host) do
      :error -> nil
      %{plug: OctomoctoWeb.LocaleController} -> nil
      _route -> if query in [nil, ""], do: localized, else: localized <> "?" <> query
    end
  end

  def init(opts), do: opts

  def call(%Plug.Conn{method: "GET"} = conn, _opts) do
    if prefixed?(conn.path_info) or bot?(conn) do
      conn
    else
      conn = put_resp_header(conn, "vary", "accept-language")
      user = conn.assigns.current_scope && conn.assigns.current_scope.user
      locale = locale(user, get_session(conn))

      case localized_path(locale, conn.request_path, conn.query_string, conn.host) do
        nil -> conn
        to -> conn |> Phoenix.Controller.redirect(to: to) |> halt()
      end
    end
  end

  def call(conn, _opts), do: conn

  defp prefixed?([first | _rest]), do: first in Locale.other_locales()
  defp prefixed?([]), do: false

  defp bot?(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent | _] -> Regex.match?(@bot, user_agent)
      [] -> true
    end
  end

  # The plug handles the first request, so only a live navigation, which
  # needs a connected socket, gets here
  def on_mount(:default, _params, session, socket) do
    {:cont,
     Phoenix.LiveView.attach_hook(socket, :locale_redirect, :handle_params, fn
       _params, uri, socket ->
         if Phoenix.LiveView.connected?(socket),
           do: redirect_live(socket, session, URI.parse(uri)),
           else: {:cont, socket}
     end)}
  end

  defp redirect_live(socket, session, uri) do
    scope = socket.assigns[:current_scope]
    locale = locale(scope && scope.user, session)

    case localized_path(locale, uri.path, uri.query, uri.host) do
      nil -> {:cont, socket}
      to -> {:halt, Phoenix.LiveView.redirect(socket, to: to)}
    end
  end
end
