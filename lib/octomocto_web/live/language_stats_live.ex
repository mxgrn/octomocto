defmodule OctomoctoWeb.LanguageStatsLive do
  @moduledoc """
  The stats page of one language, at `/stats/languages/:language`: the
  games in the days of `StatsLive` with players of the language, the most
  played first (see `Octomocto.Stats.games_in_language/3`). Each game
  links to its stats page.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, nil}

  alias Octomocto.Stats
  alias OctomoctoWeb.{GameIcons, HomeLive, StatsLive}

  def mount(%{"language" => language}, _session, socket) do
    counts = Stats.games_in_language(language, StatsLive.days())

    games =
      HomeLive.games()
      |> Enum.map(&Map.put(&1, :count, Map.get(counts, &1.id, 0)))
      |> Enum.filter(&(&1.count > 0))
      |> Enum.sort_by(& &1.count, :desc)

    {:ok,
     assign(socket,
       page_title: "#{language} stats",
       noindex: true,
       language: language,
       days: StatsLive.days(),
       games: games
     )}
  end
end
