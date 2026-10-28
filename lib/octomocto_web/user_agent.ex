defmodule OctomoctoWeb.UserAgent do
  @moduledoc """
  Gives a short, human name for the device in a User-Agent header,
  for example "Chrome on macOS".
  """

  # The order is important: Edge and Opera also say "Chrome", and Chrome also says "Safari"
  @browsers [
    {"Edg", "Edge"},
    {"OPR", "Opera"},
    {"Firefox", "Firefox"},
    {"FxiOS", "Firefox"},
    {"CriOS", "Chrome"},
    {"Chrome", "Chrome"},
    {"Safari", "Safari"}
  ]

  # iOS and Android also say "Mac OS X" and "Linux"
  @systems [
    {"iPhone", "iPhone"},
    {"iPad", "iPad"},
    {"Android", "Android"},
    {"Windows", "Windows"},
    {"CrOS", "ChromeOS"},
    {"Macintosh", "macOS"},
    {"Linux", "Linux"}
  ]

  @doc """
  Returns nil when we do not know the browser or the system.
  """
  def describe(nil), do: nil

  def describe(user_agent) do
    case {find(@browsers, user_agent), find(@systems, user_agent)} do
      {nil, nil} -> nil
      {browser, nil} -> browser
      {nil, system} -> system
      {browser, system} -> "#{browser} on #{system}"
    end
  end

  defp find(names, user_agent) do
    Enum.find_value(names, fn {token, name} ->
      if String.contains?(user_agent, token), do: name
    end)
  end
end
