defmodule OctomoctoWeb.TrainsHTML do
  use OctomoctoWeb, :html

  import OctomoctoWeb.SchulteHTML, only: [setting: 1, option: 1]

  embed_templates "trains_html/*"

  @doc "The start page with the settings, and with the given changes."
  def settings_path(settings, changes \\ %{}) do
    s = Map.merge(settings, changes)

    ~p"/trains?#{[players: s.players, switches: s.switch_count, trains: s.trains_per_house, pace: s.pace]}"
  end

  @doc "Tells what a number of switches gives: there is one more house than switches."
  def switches_hint(switches, 1), do: "#{switches + 1} houses."

  def switches_hint(switches, players) do
    switches_hint(switches, 1) <> " Each player owns #{div(switches, players)} switches."
  end

  def trains_hint(%{switch_count: switches, trains_per_house: n}),
    do: "#{n * (switches + 1)} trains."

  def pace_hint("easy"), do: "A train every 8 seconds."

  def pace_hint("normal"),
    do: "The trains come faster and faster: from 8 down to 2 seconds apart."

  def pace_hint("hard"), do: "The trains get fast early in the game."
  def pace_hint("expert"), do: "The trains get very fast very early in the game."
end
