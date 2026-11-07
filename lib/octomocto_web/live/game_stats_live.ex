defmodule OctomoctoWeb.GameStatsLive do
  @moduledoc """
  The stats page of one game, at `/stats/:game`: the 10 players, users and
  guests, with the most games in the game in the days of `StatsLive` (see
  `Octomocto.Stats.top_players/3`). The names link to the profiles.
  """
  use OctomoctoWeb, :live_view

  import OctomoctoWeb.SettingsComponents, only: [player_name: 1]

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.Stats
  alias OctomoctoWeb.{GameIcons, HomeLive, NotFoundError, StatsLive}

  def mount(%{"game" => id}, _session, socket) do
    game = Enum.find(HomeLive.games(), &(&1.id == id))
    if !game or !Stats.game?(id), do: raise(NotFoundError)

    {:ok,
     assign(socket,
       page_title: "#{game.name} stats",
       noindex: true,
       game: game,
       days: StatsLive.days(),
       players: Stats.top_players(id, StatsLive.days())
     )}
  end

  # A guest from before the guest names is "Guest"
  defp name(%{user: nil, guest: guest}), do: guest.name || "Guest"
  defp name(%{user: user}), do: player_name(user)
end
