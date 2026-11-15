defmodule OctomoctoWeb.InkTrailHTML do
  use OctomoctoWeb, :html

  embed_templates "ink_trail_html/*"

  @doc """
  The texts of the game in the language of the page, by the English text,
  for `InkTrail.elm`. The game shows a text without a translation in
  English. The game puts the values into the `{name}` parts.
  """
  def elm_texts do
    %{
      "Joining the game…" => dgettext("ink-trail", "Joining the game…"),
      "Could not join the game: {reason}" =>
        dgettext("ink-trail", "Could not join the game: {reason}"),
      "Ink Trail" => dgettext("ink-trail", "Ink Trail"),
      "Restart" => dgettext("ink-trail", "Restart"),
      "Restart game" => dgettext("ink-trail", "Restart game"),
      "You are watching this game." => dgettext("ink-trail", "You are watching this game."),
      "Watchers: {count}" => dgettext("ink-trail", "Watchers: {count}"),
      "Turn the sounds on" => dgettext("ink-trail", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("ink-trail", "Turn the sounds off"),
      # The labels of the stats, above the numbers
      "jets" => dgettext("ink-trail", "jets"),
      "score" => dgettext("ink-trail", "score"),
      "distance" => dgettext("ink-trail", "distance"),
      "mistakes" => dgettext("ink-trail", "mistakes"),
      "Correct in a row" => dgettext("ink-trail", "Correct in a row"),
      "Well followed!" => dgettext("ink-trail", "Well followed!"),
      "Watch the leader" => dgettext("ink-trail", "Watch the leader"),
      "Missed. Watch the trail ahead" => dgettext("ink-trail", "Missed. Watch the trail ahead"),
      "One jet further behind!" => dgettext("ink-trail", "One jet further behind!"),
      # For screen readers
      "Cave {number}" => dgettext("ink-trail", "Cave {number}"),
      "Game over!" => dgettext("ink-trail", "Game over!"),
      "Best distance {distance}" => dgettext("ink-trail", "Best distance {distance}"),
      "Play again at distance {distance}" =>
        dgettext("ink-trail", "Play again at distance {distance}"),
      "Best results" => dgettext("ink-trail", "Best results"),
      "Or try {game}" => dgettext("ink-trail", "Or try {game}"),
      "Sign in" => dgettext("ink-trail", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("ink-trail", "{sign_in} to keep your scores."),
      "{feed} to keep Octomocto ad-free." =>
        dgettext("ink-trail", "{feed} to keep Octomocto ad-free."),
      "Support the author" => dgettext("ink-trail", "Support the author")
    }
  end

  @doc """
  The texts with a number in the language of the page, for `InkTrail.elm`:
  each plural form of the language, by its index in the plural rule (see
  `Gettext.Plural`). The game puts the number into the `{count}` part.
  """
  def elm_plurals do
    %{
      "Follow {count} jets behind" =>
        plural_forms(
          dngettext_noop("ink-trail", "Follow %{count} jet behind", "Follow %{count} jets behind")
        ),
      "The player follows {count} jets behind" =>
        plural_forms(
          dngettext_noop(
            "ink-trail",
            "The player follows %{count} jet behind",
            "The player follows %{count} jets behind"
          )
        ),
      "{count} mistakes" =>
        plural_forms(dngettext_noop("ink-trail", "%{count} mistake", "%{count} mistakes"))
    }
  end

  # For each form, a number that has this form gives the text of the form
  defp plural_forms({singular, plural}) do
    locale = Gettext.get_locale(OctomoctoWeb.Gettext)

    for form <- 0..(Gettext.Plural.nplurals(locale) - 1) do
      n = Enum.find(0..200, &(Gettext.Plural.plural(locale, &1) == form))

      OctomoctoWeb.Gettext
      |> Gettext.dngettext("ink-trail", singular, plural, n)
      |> String.replace(Integer.to_string(n), "{count}")
    end
  end
end
