defmodule OctomoctoWeb.TrainsHTML do
  use OctomoctoWeb, :html

  alias OctomoctoWeb.GamePageComponents

  embed_templates "trains_html/*"

  @doc """
  The texts of the game in the language of the page, by the English text,
  for `Trains.elm`. The game shows a text without a translation in
  English. The game puts the values into the `{name}` parts.
  """
  def elm_texts do
    %{
      "Joining the game…" => dgettext("trains", "Joining the game…"),
      "Could not join the game: {reason}" =>
        dgettext("trains", "Could not join the game: {reason}"),
      "Right on Track" => dgettext("trains", "Right on Track"),
      "Level {level}" => dgettext("trains", "Level {level}"),
      "Click the switches to send each train to the house with its colors." =>
        dgettext("trains", "Click the switches to send each train to the house with its colors."),
      "Send each train to the house with its colors. You can flip only the switches in your color." =>
        dgettext(
          "trains",
          "Send each train to the house with its colors. You can flip only the switches in your color."
        ),
      "You are watching this game." => dgettext("trains", "You are watching this game."),
      "Watchers: {count}" => dgettext("trains", "Watchers: {count}"),
      # The labels of the stats, above the numbers
      "correct" => dgettext("trains", "correct"),
      "train" => dgettext("trains", "train"),
      "Copied!" => dgettext("trains", "Copied!"),
      "Copy link" => dgettext("trains", "Copy link"),
      "{name} (you)" => dgettext("trains", "{name} (you)"),
      "Menu" => dgettext("trains", "Menu"),
      "New board" => dgettext("trains", "New board"),
      "Turn the sounds on" => dgettext("trains", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("trains", "Turn the sounds off"),
      "Waiting for players" => dgettext("trains", "Waiting for players"),
      "{players} of {needed} players are in" =>
        dgettext("trains", "{players} of {needed} players are in"),
      "Send the link to the other players." =>
        dgettext("trains", "Send the link to the other players."),
      "{correct} of {total} trains got home" =>
        dgettext("trains", "{correct} of {total} trains got home"),
      "Perfect!" => dgettext("trains", "Perfect!"),
      "Good work." => dgettext("trains", "Good work."),
      "Try again with a new layout." => dgettext("trains", "Try again with a new layout."),
      "Play again" => dgettext("trains", "Play again"),
      "Change settings" => dgettext("trains", "Change settings"),
      "{name} changes the settings…" => dgettext("trains", "{name} changes the settings…"),
      "The {color} player changes the settings…" =>
        dgettext("trains", "The {color} player changes the settings…"),
      "Or try {game}" => dgettext("trains", "Or try {game}"),
      "Sign in" => dgettext("trains", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("trains", "{sign_in} to keep your scores."),
      "Support the author" => dgettext("trains", "Support the author"),
      # The end of a round of the campaign
      "Not enough trains got home" => dgettext("trains", "Not enough trains got home"),
      "{correct} of {total} trains got home. {pass} are needed." =>
        dgettext("trains", "{correct} of {total} trains got home. {pass} are needed."),
      "You finished the campaign!" => dgettext("trains", "You finished the campaign!"),
      "{correct} of {total} trains got home." =>
        dgettext("trains", "{correct} of {total} trains got home."),
      "Level {level} done · {correct} of {total} trains got home." =>
        dgettext("trains", "Level {level} done · {correct} of {total} trains got home."),
      "Try again" => dgettext("trains", "Try again"),
      "Next level" => dgettext("trains", "Next level"),
      "Back to the map" => dgettext("trains", "Back to the map")
    }
    |> Map.merge(
      Map.new(GamePageComponents.color_names(), &{&1, GamePageComponents.color_name(&1)})
    )
  end

  @doc """
  The texts with a number in the language of the page, for `Trains.elm`:
  each plural form of the language, by its index in the plural rule (see
  `Gettext.Plural`). The game puts the number into the `{count}` part.
  """
  def elm_plurals do
    %{
      "{count} switches" =>
        plural_forms(dngettext_noop("trains", "%{count} switch", "%{count} switches")),
      "{count} errors" =>
        plural_forms(dngettext_noop("trains", "%{count} error", "%{count} errors"))
    }
  end

  # For each form, a number that has this form gives the text of the form
  defp plural_forms({singular, plural}) do
    locale = Gettext.get_locale(OctomoctoWeb.Gettext)

    for form <- 0..(Gettext.Plural.nplurals(locale) - 1) do
      n = Enum.find(0..200, &(Gettext.Plural.plural(locale, &1) == form))

      OctomoctoWeb.Gettext
      |> Gettext.dngettext("trains", singular, plural, n)
      |> String.replace(Integer.to_string(n), "{count}")
    end
  end
end
