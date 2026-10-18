defmodule OctomoctoWeb.Locale do
  @moduledoc """
  The languages of the pages. An English page has no prefix. A page in a
  different language has the language as the prefix, for example
  `/pt/memory`.

  Only some games have translations. The router sends a prefixed URL of a
  game without translations to the English page (see
  `OctomoctoWeb.LocaleController`). A text without a translation stays in
  English, so a translation can be partial.

  As a plug, it sets the language for the request. As an `on_mount` hook,
  it sets the language for the LiveView. Each one assigns `:locale`.
  """
  import Plug.Conn

  @names %{
    "en" => "English",
    "pt" => "Português",
    "de" => "Deutsch",
    "ru" => "Русский",
    "fr" => "Français",
    "uk" => "Українська"
  }

  # The value of the `lang` and `hreflang` attributes. The Portuguese
  # translations are Brazilian.
  @html_langs %{
    "en" => "en",
    "pt" => "pt-BR",
    "de" => "de",
    "ru" => "ru",
    "fr" => "fr",
    "uk" => "uk"
  }

  # The games with translations, by language
  @games %{
    "pt" => ["memory"],
    "de" => ["memory"],
    "ru" => ["memory"],
    "fr" => ["memory"],
    "uk" => ["memory"]
  }

  def init(locale), do: locale

  def call(conn, locale) do
    Gettext.put_locale(OctomoctoWeb.Gettext, locale)
    assign(conn, :locale, locale)
  end

  def on_mount(locale, _params, _session, socket) do
    Gettext.put_locale(OctomoctoWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  @doc "The value of the `lang` attribute for the language of the process."
  def html_lang, do: Map.fetch!(@html_langs, Gettext.get_locale(OctomoctoWeb.Gettext))

  @doc "The path in the language, for example `/pt/memory` for `/memory`."
  def path("en", path), do: path
  def path(locale, path), do: "/" <> locale <> path

  @doc "The path of the page of a game in the language, or in English when the game has no translations."
  def game_path(locale, %{id: id, path: path}) do
    if id in Map.get(@games, locale, []), do: path(locale, path), else: path
  end

  @doc """
  The links to the same page in each language of the game, for the
  language switcher. The `path` is the English path of the page.
  """
  def languages(game, current, path) do
    for locale <- locales(game) do
      %{
        locale: locale,
        name: Map.fetch!(@names, locale),
        path: path(locale, path),
        current: locale == current
      }
    end
  end

  @doc """
  The URLs of the same page in each language of the game, for search
  engines, as `{hreflang, url}`. English is also the default.
  """
  def alternate_urls(game, path) do
    base = OctomoctoWeb.Endpoint.url()

    Enum.map(locales(game), &{Map.fetch!(@html_langs, &1), base <> path(&1, path)}) ++
      [{"x-default", base <> path}]
  end

  @pt_months ~w(jan. fev. mar. abr. mai. jun. jul. ago. set. out. nov. dez.)

  @de_months ~w(Jan. Feb. März Apr. Mai Juni Juli Aug. Sept. Okt. Nov. Dez.)

  @ru_months ~w(янв. февр. марта апр. мая июня июля авг. сент. окт. нояб. дек.)

  @fr_months ~w(janv. févr. mars avr. mai juin juil. août sept. oct. nov. déc.)

  @uk_months ~w(січ. лют. берез. квіт. трав. черв. лип. серп. верес. жовт. листоп. груд.)

  @doc "A short date in the language of the process, for example \"Oct 17\", \"17 de out.\", \"17. Okt.\", \"17 окт.\", \"17 oct.\" or \"17 жовт.\"."
  def short_date(date) do
    case Gettext.get_locale(OctomoctoWeb.Gettext) do
      "pt" ->
        Calendar.strftime(date, "%-d de %b",
          abbreviated_month_names: &Enum.at(@pt_months, &1 - 1)
        )

      "de" ->
        Calendar.strftime(date, "%-d. %b", abbreviated_month_names: &Enum.at(@de_months, &1 - 1))

      "ru" ->
        Calendar.strftime(date, "%-d %b", abbreviated_month_names: &Enum.at(@ru_months, &1 - 1))

      "fr" ->
        Calendar.strftime(date, "%-d %b", abbreviated_month_names: &Enum.at(@fr_months, &1 - 1))

      "uk" ->
        Calendar.strftime(date, "%-d %b", abbreviated_month_names: &Enum.at(@uk_months, &1 - 1))

      _ ->
        Calendar.strftime(date, "%b %-d")
    end
  end

  # English, then the languages with translations of the game
  defp locales(game) do
    ["en" | for({locale, games} <- @games, game in games, do: locale)]
  end
end
