defmodule OctomoctoWeb.EchoHTML do
  use OctomoctoWeb, :html

  alias OctomoctoWeb.GamePageComponents

  embed_templates "echo_html/*"

  @doc """
  The texts of the game in the language of the page, by the English text,
  for `Echo.elm`. The game shows a text without a translation in English.
  The game puts the values into the `{name}` parts. The pad names and
  shapes are for screen readers.
  """
  def elm_texts do
    %{
      "Joining the game…" => dgettext("echo", "Joining the game…"),
      "Could not join the game: {reason}" =>
        dgettext("echo", "Could not join the game: {reason}"),
      "Echo" => dgettext("echo", "Echo"),
      "Watch the pads light up, then tap them in the same order." =>
        dgettext("echo", "Watch the pads light up, then tap them in the same order."),
      "Repeat the sequence, then add a pad of your choice." =>
        dgettext("echo", "Repeat the sequence, then add a pad of your choice."),
      "You are watching this game." => dgettext("echo", "You are watching this game."),
      "Best results" => dgettext("echo", "Best results"),
      "Watchers: {count}" => dgettext("echo", "Watchers: {count}"),
      "Turn the sounds on" => dgettext("echo", "Turn the sounds on"),
      "Turn the sounds off" => dgettext("echo", "Turn the sounds off"),
      "Hide the shapes on the pads" => dgettext("echo", "Hide the shapes on the pads"),
      "Show the shapes on the pads" => dgettext("echo", "Show the shapes on the pads"),
      "Restart game" => dgettext("echo", "Restart game"),
      "Copied!" => dgettext("echo", "Copied!"),
      "Copy link" => dgettext("echo", "Copy link"),
      "turn" => dgettext("echo", "turn"),
      "out" => dgettext("echo", "out"),
      "{name} (you)" => dgettext("echo", "{name} (you)"),
      "The {color} player" => dgettext("echo", "The {color} player"),
      "Tap Go to start." => dgettext("echo", "Tap Go to start."),
      "Watch closely…" => dgettext("echo", "Watch closely…"),
      "Your turn: {taps} to go." => dgettext("echo", "Your turn: {taps} to go."),
      "You are out. Watch the others play." =>
        dgettext("echo", "You are out. Watch the others play."),
      "You start. Tap any pad to add it to the sequence." =>
        dgettext("echo", "You start. Tap any pad to add it to the sequence."),
      "Your turn: repeat the sequence. {taps} to go." =>
        dgettext("echo", "Your turn: repeat the sequence. {taps} to go."),
      "Now add a pad of your choice." => dgettext("echo", "Now add a pad of your choice."),
      "{name} starts the sequence." => dgettext("echo", "{name} starts the sequence."),
      "{name} repeats the sequence." => dgettext("echo", "{name} repeats the sequence."),
      "{name} adds a pad." => dgettext("echo", "{name} adds a pad."),
      "1 tap" => dgettext("echo", "1 tap"),
      "{count} taps" => dgettext("echo", "{count} taps"),
      "1 pad" => dgettext("echo", "1 pad"),
      "{count} pads" => dgettext("echo", "{count} pads"),
      "{color} pad, {shape}" => dgettext("echo", "{color} pad, {shape}"),
      "Orange" => dgettext("echo", "Orange"),
      "Blue" => dgettext("echo", "Blue"),
      "Yellow" => dgettext("echo", "Yellow"),
      "Violet" => dgettext("echo", "Violet"),
      "Lime" => dgettext("echo", "Lime"),
      "Red" => dgettext("echo", "Red"),
      "Teal" => dgettext("echo", "Teal"),
      "Pink" => dgettext("echo", "Pink"),
      "circle" => dgettext("echo", "circle"),
      "triangle" => dgettext("echo", "triangle"),
      "square" => dgettext("echo", "square"),
      "diamond" => dgettext("echo", "diamond"),
      "plus" => dgettext("echo", "plus"),
      "star" => dgettext("echo", "star"),
      "cross" => dgettext("echo", "cross"),
      "hexagon" => dgettext("echo", "hexagon"),
      "Start game" => dgettext("echo", "Start game"),
      "Level {level}" => dgettext("echo", "Level {level}"),
      "Go" => dgettext("echo", "Go"),
      "tap to play" => dgettext("echo", "tap to play"),
      "watch" => dgettext("echo", "watch"),
      "your turn" => dgettext("echo", "your turn"),
      "repeat" => dgettext("echo", "repeat"),
      "add a pad" => dgettext("echo", "add a pad"),
      "Waiting for players" => dgettext("echo", "Waiting for players"),
      "{players} of {needed} players are in" =>
        dgettext("echo", "{players} of {needed} players are in"),
      "Send the link to the other players. The game starts when all of them are in." =>
        dgettext(
          "echo",
          "Send the link to the other players. The game starts when all of them are in."
        ),
      "Game over" => dgettext("echo", "Game over"),
      "You repeated {pads}." => dgettext("echo", "You repeated {pads}."),
      "You win!" => dgettext("echo", "You win!"),
      "{name} wins!" => dgettext("echo", "{name} wins!"),
      "The sequence had {pads}." => dgettext("echo", "The sequence had {pads}."),
      "Play again" => dgettext("echo", "Play again"),
      "Or try {game}" => dgettext("echo", "Or try {game}"),
      "Sign in" => dgettext("echo", "Sign in"),
      "{sign_in} to keep your scores." => dgettext("echo", "{sign_in} to keep your scores."),
      "Enjoying Octomocto? {feed} to keep it ad-free." =>
        dgettext("echo", "Enjoying Octomocto? {feed} to keep it ad-free."),
      "Feed Octo & Mocto" => dgettext("echo", "Feed Octo & Mocto")
    }
    |> Map.merge(
      Map.new(GamePageComponents.color_names(), &{&1, GamePageComponents.color_name(&1)})
    )
  end
end
