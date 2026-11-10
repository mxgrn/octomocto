defmodule OctomoctoWeb.LanguageStatsLive do
  @moduledoc """
  The stats page of one language, at `/stats/languages/:language`: the
  games in the days of `StatsLive` with players of the language, the most
  played first (see `Octomocto.Stats.games_in_language/3`), each with a
  graph of its games per day. Each game links to its stats page.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.Stats
  alias OctomoctoWeb.{GameIcons, HomeLive, PlayerLive, StatsLive}

  def mount(%{"language" => language}, _session, socket) do
    {:ok, assign(socket, page_title: "#{language} stats", noindex: true, language: language)}
  end

  def handle_params(params, _uri, socket) do
    today? = StatsLive.today?(params)
    {count, last} = StatsLive.period(today?)
    activity = Stats.games_in_language(socket.assigns.language, count, last)

    games =
      HomeLive.games()
      |> Enum.filter(&Map.has_key?(activity, &1.id))
      |> Enum.map(fn game ->
        days = Map.fetch!(activity, game.id)
        game |> Map.put(:days, days) |> Map.put(:count, Enum.sum(days))
      end)
      |> Enum.sort_by(& &1.count, :desc)

    {:noreply, assign(socket, today?: today?, games: games)}
  end
end
