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
      "Back to the settings" => dgettext("memory", "Back to the settings"),
      "Memory" => dgettext("memory", "Memory"),
      "Find the pairs of cards with the same image." =>
        dgettext("memory", "Find the pairs of cards with the same image."),
      "Find the triplets of cards with the same image." =>
        dgettext("memory", "Find the triplets of cards with the same image."),
      "This game is full, so you can only watch it." =>
        dgettext("memory", "This game is full, so you can only watch it."),
      "Latest games and best results" => dgettext("memory", "Latest games and best results"),
      "Turn the sounds on" => dgettext("memory", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("memory", "Turn the sounds off"),
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
      "Or try {game}" => dgettext("memory", "Or try {game}"),
      "Sign in" => dgettext("memory", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("memory", "{sign_in} to keep your scores.")
    }
    |> Map.merge(
      Map.new(GamePageComponents.color_names(), &{&1, GamePageComponents.color_name(&1)})
    )
  end
end
