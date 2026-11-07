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
    activity = Stats.games_in_language(language, StatsLive.days())

    games =
      HomeLive.games()
      |> Enum.filter(&Map.has_key?(activity, &1.id))
      |> Enum.map(fn game ->
        days = Map.fetch!(activity, game.id)
        game |> Map.put(:days, days) |> Map.put(:count, Enum.sum(days))
      end)
      |> Enum.sort_by(& &1.count, :desc)

    {:ok,
     assign(socket,
       page_title: "#{language} stats",
       noindex: true,
       language: language,
       days: StatsLive.days(),
       games: games,
       # All sparklines have the same scale, as the bars of the counts
       most_in_day: games |> Enum.flat_map(& &1.days) |> Enum.max(fn -> 0 end)
     )}
  end
end
