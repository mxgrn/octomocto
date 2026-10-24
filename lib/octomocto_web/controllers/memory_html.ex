defmodule OctomoctoWeb.MemoryHTML do
  use OctomoctoWeb, :html

  alias OctomoctoWeb.GamePageComponents

  embed_templates "memory_html/*"

  @doc """
  The texts of the game in the language of the page, by the English text,
  for `Memory.elm`. The game shows a text without a translation in
  English. The game puts the values into the `{name}` parts.
  """
  def elm_texts do
    %{
      "Joining the game…" => dgettext("memory", "Joining the game…"),
      "Could not join the game: {reason}" =>
        dgettext("memory", "Could not join the game: {reason}"),
      "Memory" => dgettext("memory", "Memory"),
      "Find the pairs of cards with the same image." =>
        dgettext("memory", "Find the pairs of cards with the same image."),
      "Find the triplets of cards with the same image." =>
        dgettext("memory", "Find the triplets of cards with the same image."),
      "This game is full, so you can only watch it." =>
        dgettext("memory", "This game is full, so you can only watch it."),
      "Best results" => dgettext("memory", "Best results"),
      "Turn the sounds on" => dgettext("memory", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("memory", "Turn the sounds off"),
      "Watchers: {count}" => dgettext("memory", "Watchers: {count}"),
      "Restart game" => dgettext("memory", "Restart game"),
      "Copied!" => dgettext("memory", "Copied!"),
      "Copy link" => dgettext("memory", "Copy link"),
      "time" => dgettext("memory", "time"),
      "accuracy" => dgettext("memory", "accuracy"),
      "Accuracy" => dgettext("memory", "Accuracy"),
      "turn" => dgettext("memory", "turn"),
      "{name} (you)" => dgettext("memory", "{name} (you)"),
      "Waiting for players" => dgettext("memory", "Waiting for players"),
      "{players} of {needed} players are in" =>
        dgettext("memory", "{players} of {needed} players are in"),
      "Send the link to the other players. The game starts when all of them are in." =>
        dgettext(
          "memory",
          "Send the link to the other players. The game starts when all of them are in."
        ),
      "Done!" => dgettext("memory", "Done!"),
      "You win!" => dgettext("memory", "You win!"),
      "{name} wins!" => dgettext("memory", "{name} wins!"),
      "The {color} player wins!" => dgettext("memory", "The {color} player wins!"),
      "It's a tie!" => dgettext("memory", "It's a tie!"),
      "Time {time}" => dgettext("memory", "Time {time}"),
      "Accuracy {accuracy}" => dgettext("memory", "Accuracy {accuracy}"),
      "Play again" => dgettext("memory", "Play again"),
      "Change settings" => dgettext("memory", "Change settings"),
      "{name} changes the settings…" => dgettext("memory", "{name} changes the settings…"),
      "The {color} player changes the settings…" =>
        dgettext("memory", "The {color} player changes the settings…"),
      "Or try {game}" => dgettext("memory", "Or try {game}"),
      "Sign in" => dgettext("memory", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("memory", "{sign_in} to keep your scores."),
      "Level {level}" => dgettext("memory", "Level {level}"),
      "Back to the map" => dgettext("memory", "Back to the map"),
      "Wrong card!" => dgettext("memory", "Wrong card!"),
      "You cleared {cleared} of {cards} cards." =>
        dgettext("memory", "You cleared {cleared} of {cards} cards."),
      "You finished the campaign!" => dgettext("memory", "You finished the campaign!"),
      "Perfect!" => dgettext("memory", "Perfect!"),
      "Level {level} done" => dgettext("memory", "Level {level} done"),
      "Try again" => dgettext("memory", "Try again"),
      "Next level" => dgettext("memory", "Next level"),
      "bombs" => dgettext("memory", "bombs"),
      "demining" => dgettext("memory", "demining"),
      "Deminer" => dgettext("memory", "Deminer"),
      "Out" => dgettext("memory", "Out"),
      "You found the last bomb! Turn another bomb now to demine the field, or any other card to play on." =>
        dgettext(
          "memory",
          "You found the last bomb! Turn another bomb now to demine the field, or any other card to play on."
        ),
      "{name} found the last bomb and can demine the field…" =>
        dgettext("memory", "{name} found the last bomb and can demine the field…"),
      "The {color} player found the last bomb and can demine the field…" =>
        dgettext("memory", "The {color} player found the last bomb and can demine the field…"),
      "Demine the field now: turn all other bombs. A wrong card puts you out." =>
        dgettext(
          "memory",
          "Demine the field now: turn all other bombs. A wrong card puts you out."
        ),
      "{name} demines the field…" => dgettext("memory", "{name} demines the field…"),
      "The {color} player demines the field…" =>
        dgettext("memory", "The {color} player demines the field…"),
      "Boom!" => dgettext("memory", "Boom!"),
      "You turned a bomb that was seen." =>
        dgettext("memory", "You turned a bomb that was seen."),
      "The demining failed: the last card was not a bomb." =>
        dgettext("memory", "The demining failed: the last card was not a bomb."),
      "You demined the field!" => dgettext("memory", "You demined the field!"),
      "The field wasn't demined." => dgettext("memory", "The field wasn't demined.")
    }
    |> Map.merge(
      Map.new(GamePageComponents.color_names(), &{&1, GamePageComponents.color_name(&1)})
    )
  end
end
