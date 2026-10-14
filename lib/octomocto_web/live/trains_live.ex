defmodule OctomoctoWeb.TrainsLive do
  use OctomoctoWeb, :live_view

  import OctomoctoWeb.SchulteHTML, only: [setting: 1, option: 1]

  alias Octomocto.Trains

  def mount(_params, _session, socket) do
    {:ok, assign(socket, seo())}
  end

  @doc "The title and the description of the Right on Track pages, for search engines."
  def seo do
    [
      page_title: "Right on Track: Train Switching Puzzle",
      page_description:
        "Click the switches to send each train to the house with its colors. A free train puzzle game in your browser, alone or together with up to 3 friends."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)

    {:noreply,
     assign(socket, settings: settings, switch_counts: Trains.switch_counts(settings.players))}
  end

  def handle_event("new_game", _params, socket) do
    id = Trains.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/trains/#{id}")}
  end

  # One player, 12 switches, 2 trains for each house and the normal pace,
  # when the params do not say otherwise. The switches must divide equally
  # between the players.
  defp settings(params) do
    players = int_param(params["players"], 1..4, 1)
    switches = int_param(params["switches"], 1..12, 12)

    %{
      players: players,
      switch_count: Trains.fit_switch_count(switches, players),
      trains_per_house: int_param(params["trains"], 1..7, 2),
      pace: if(params["pace"] in Trains.paces(), do: params["pace"], else: "normal")
    }
  end

  defp int_param(value, range, default) do
    case Integer.parse(value || "") do
      {n, ""} -> if n in range, do: n, else: default
      _ -> default
    end
  end

  # The start page with the settings, and with the given changes
  defp settings_path(settings, changes) do
    s = Map.merge(settings, changes)

    ~p"/trains?#{[players: s.players, switches: s.switch_count, trains: s.trains_per_house, pace: s.pace]}"
  end

  # Tells what a number of switches gives: there is one more house than switches
  defp switches_hint(switches, 1), do: "#{switches + 1} houses."

  defp switches_hint(switches, players) do
    switches_hint(switches, 1) <> " Each player owns #{div(switches, players)} switches."
  end

  defp trains_hint(%{switch_count: switches, trains_per_house: n}),
    do: "#{n * (switches + 1)} trains."

  defp pace_hint("easy"), do: "A train every 8 seconds."

  defp pace_hint("normal"),
    do: "The trains come faster and faster: from 8 down to 2 seconds apart."

  defp pace_hint("hard"), do: "The trains get fast early in the game."
  defp pace_hint("expert"), do: "The trains get very fast very early in the game."
end
