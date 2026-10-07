defmodule OctomoctoWeb.SchulteHTML do
  use OctomoctoWeb, :html

  embed_templates "schulte_html/*"

  @doc "A title for the settings of a leaderboard, for example \"Classic board · 2 players\"."
  def settings_title(%{"type" => type, "players" => players}) do
    board = if type == "classic", do: "Classic board", else: "Random board"
    players = if players == 1, do: "solo", else: "#{players} players"
    "#{board} · #{players}"
  end

  @doc "Shows the time as minutes, seconds and tenths, for example \"1:05.3\"."
  def format_time(ms) do
    seconds = div(ms, 1000)
    tenths = div(rem(ms, 1000), 100)
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}.#{tenths}"
  end

  # Do not show the full email of a user to other players.
  def player_name(nil), do: "Guest"
  def player_name(%{name: name}) when is_binary(name) and name != "", do: name
  def player_name(%{telegram_username: username}) when is_binary(username), do: "@" <> username
  def player_name(%{email: email}), do: email |> String.split("@") |> hd()
end
