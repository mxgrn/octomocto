defmodule OctomoctoWeb.SetGameHTML do
  use OctomoctoWeb, :html

  alias OctomoctoWeb.GamePageComponents

  embed_templates "set_game_html/*"

  @doc """
  The texts of the game in the language of the page, by the English text,
  for `SetGame.elm`. The game shows a text without a translation in
  English. The game puts the values into the `{name}` parts.
  """
  def elm_texts do
    %{
      "Joining the game…" => dgettext("set", "Joining the game…"),
      "Could not join the game: {reason}" => dgettext("set", "Could not join the game: {reason}"),
      "Set" => dgettext("set", "Set"),
      "Find 3 cards where each feature is all the same or all different." =>
        dgettext(
          "set",
          "Find 3 cards where each feature is all the same or all different."
        ),
      "You are watching this game." => dgettext("set", "You are watching this game."),
      "Watchers: {count}" => dgettext("set", "Watchers: {count}"),
      "Hint" => dgettext("set", "Hint"),
      "Next hint" => dgettext("set", "Next hint"),
      "No more hints" => dgettext("set", "No more hints"),
      "Menu" => dgettext("set", "Menu"),
      "Restart game" => dgettext("set", "Restart game"),
      "Turn the sounds on" => dgettext("set", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("set", "Turn the sounds off"),
      "Copied!" => dgettext("set", "Copied!"),
      "Copy link" => dgettext("set", "Copy link"),
      "time" => dgettext("set", "time"),
      "deck" => dgettext("set", "deck"),
      "{name} (you)" => dgettext("set", "{name} (you)"),
      "last set" => dgettext("set", "last set"),
      "Waiting for players" => dgettext("set", "Waiting for players"),
      "{players} of {needed} players are in" =>
        dgettext(
          "set",
          "{players} of {needed} players are in"
        ),
      "Send the link to the other players. The game starts when all of them are in." =>
        dgettext(
          "set",
          "Send the link to the other players. The game starts when all of them are in."
        ),
      "Done!" => dgettext("set", "Done!"),
      "You win!" => dgettext("set", "You win!"),
      "{name} wins!" => dgettext("set", "{name} wins!"),
      "The {color} player wins!" => dgettext("set", "The {color} player wins!"),
      "It's a tie!" => dgettext("set", "It's a tie!"),
      "Time {time}" => dgettext("set", "Time {time}"),
      "{name} changes the settings…" => dgettext("set", "{name} changes the settings…"),
      "The {color} player changes the settings…" =>
        dgettext(
          "set",
          "The {color} player changes the settings…"
        ),
      "Play again" => dgettext("set", "Play again"),
      "Change settings" => dgettext("set", "Change settings"),
      "Best results" => dgettext("set", "Best results"),
      "Or try {game}" => dgettext("set", "Or try {game}"),
      "Sign in" => dgettext("set", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("set", "{sign_in} to keep your scores."),
      "{feed} to keep Octomocto ad-free." => dgettext("set", "{feed} to keep Octomocto ad-free."),
      "Support the author" => dgettext("set", "Support the author"),
      # The clues of the Hint button, one for each feature of a set
      "Each of them has 1 shape" => dgettext("set", "Each of them has 1 shape"),
      "Each of them has 2 shapes" => dgettext("set", "Each of them has 2 shapes"),
      "Each of them has 3 shapes" => dgettext("set", "Each of them has 3 shapes"),
      "Each of them has the diamond shape" =>
        dgettext(
          "set",
          "Each of them has the diamond shape"
        ),
      "Each of them has the oval shape" => dgettext("set", "Each of them has the oval shape"),
      "Each of them has the squiggle shape" =>
        dgettext(
          "set",
          "Each of them has the squiggle shape"
        ),
      "Each of them is solid" => dgettext("set", "Each of them is solid"),
      "Each of them is striped" => dgettext("set", "Each of them is striped"),
      "Each of them is open" => dgettext("set", "Each of them is open"),
      "Each of them is red" => dgettext("set", "Each of them is red"),
      "Each of them is green" => dgettext("set", "Each of them is green"),
      "Each of them is purple" => dgettext("set", "Each of them is purple"),
      "Each of them has a different number of shapes" =>
        dgettext(
          "set",
          "Each of them has a different number of shapes"
        ),
      "Each of them has a different shape" =>
        dgettext(
          "set",
          "Each of them has a different shape"
        ),
      "Each of them has a different shading" =>
        dgettext(
          "set",
          "Each of them has a different shading"
        ),
      "Each of them has a different color" =>
        dgettext(
          "set",
          "Each of them has a different color"
        ),
      # Why 3 cards are not a set, one for each feature that two cards have
      # and the third card does not have
      "Two cards have 1 shape, but one has 2 shapes." =>
        dgettext(
          "set",
          "Two cards have 1 shape, but one has 2 shapes."
        ),
      "Two cards have 1 shape, but one has 3 shapes." =>
        dgettext(
          "set",
          "Two cards have 1 shape, but one has 3 shapes."
        ),
      "Two cards have 2 shapes, but one has 1 shape." =>
        dgettext(
          "set",
          "Two cards have 2 shapes, but one has 1 shape."
        ),
      "Two cards have 2 shapes, but one has 3 shapes." =>
        dgettext(
          "set",
          "Two cards have 2 shapes, but one has 3 shapes."
        ),
      "Two cards have 3 shapes, but one has 1 shape." =>
        dgettext(
          "set",
          "Two cards have 3 shapes, but one has 1 shape."
        ),
      "Two cards have 3 shapes, but one has 2 shapes." =>
        dgettext(
          "set",
          "Two cards have 3 shapes, but one has 2 shapes."
        ),
      "Two cards have diamonds, but one has ovals." =>
        dgettext(
          "set",
          "Two cards have diamonds, but one has ovals."
        ),
      "Two cards have diamonds, but one has squiggles." =>
        dgettext(
          "set",
          "Two cards have diamonds, but one has squiggles."
        ),
      "Two cards have ovals, but one has diamonds." =>
        dgettext(
          "set",
          "Two cards have ovals, but one has diamonds."
        ),
      "Two cards have ovals, but one has squiggles." =>
        dgettext(
          "set",
          "Two cards have ovals, but one has squiggles."
        ),
      "Two cards have squiggles, but one has diamonds." =>
        dgettext(
          "set",
          "Two cards have squiggles, but one has diamonds."
        ),
      "Two cards have squiggles, but one has ovals." =>
        dgettext(
          "set",
          "Two cards have squiggles, but one has ovals."
        ),
      "Two cards are solid, but one is striped." =>
        dgettext(
          "set",
          "Two cards are solid, but one is striped."
        ),
      "Two cards are solid, but one is open." =>
        dgettext(
          "set",
          "Two cards are solid, but one is open."
        ),
      "Two cards are striped, but one is solid." =>
        dgettext(
          "set",
          "Two cards are striped, but one is solid."
        ),
      "Two cards are striped, but one is open." =>
        dgettext(
          "set",
          "Two cards are striped, but one is open."
        ),
      "Two cards are open, but one is solid." =>
        dgettext(
          "set",
          "Two cards are open, but one is solid."
        ),
      "Two cards are open, but one is striped." =>
        dgettext(
          "set",
          "Two cards are open, but one is striped."
        ),
      "Two cards are red, but one is green." =>
        dgettext(
          "set",
          "Two cards are red, but one is green."
        ),
      "Two cards are red, but one is purple." =>
        dgettext(
          "set",
          "Two cards are red, but one is purple."
        ),
      "Two cards are green, but one is red." =>
        dgettext(
          "set",
          "Two cards are green, but one is red."
        ),
      "Two cards are green, but one is purple." =>
        dgettext(
          "set",
          "Two cards are green, but one is purple."
        ),
      "Two cards are purple, but one is red." =>
        dgettext(
          "set",
          "Two cards are purple, but one is red."
        ),
      "Two cards are purple, but one is green." =>
        dgettext(
          "set",
          "Two cards are purple, but one is green."
        )
    }
    |> Map.merge(
      Map.new(GamePageComponents.color_names(), &{&1, GamePageComponents.color_name(&1)})
    )
  end

  @doc """
  The name of each card in the language of the page, by the number of the
  card (see `SetGame.elm`), for screen readers. For example, "2 green
  striped ovals".
  """
  def card_names do
    for card <- 0..80 do
      [count, shape, shading, color] = Integer.digits(card + 81, 3) |> tl() |> Enum.reverse()
      count = count + 1

      values = %{
        color: Enum.at(colors(), color),
        shading: Enum.at(shadings(), shading)
      }

      case shape do
        0 ->
          dngettext(
            "set",
            "%{count} %{color} %{shading} diamond",
            "%{count} %{color} %{shading} diamonds",
            count,
            values
          )

        1 ->
          dngettext(
            "set",
            "%{count} %{color} %{shading} oval",
            "%{count} %{color} %{shading} ovals",
            count,
            values
          )

        2 ->
          dngettext(
            "set",
            "%{count} %{color} %{shading} squiggle",
            "%{count} %{color} %{shading} squiggles",
            count,
            values
          )
      end
    end
  end

  # The colors and the shadings of the cards, in the order of their digits
  defp colors,
    do: [dgettext("set", "red"), dgettext("set", "green"), dgettext("set", "purple")]

  defp shadings,
    do: [dgettext("set", "solid"), dgettext("set", "striped"), dgettext("set", "open")]
end
