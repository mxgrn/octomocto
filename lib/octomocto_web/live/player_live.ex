defmodule OctomoctoWeb.PlayerLive do
  @moduledoc """
  The public profile page of a user or a guest, at `/players/:public_id`
  (see `Octomocto.Players`): the date of the first visit that the site
  saved, the games played in all and in each game, and the number of
  friends of a user. Anyone can open it.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, nil}

  alias Octomocto.Players
  alias OctomoctoWeb.{GameIcons, HomeLive, NotFoundError}

  def mount(%{"public_id" => public_id}, _session, socket) do
    profile = Players.profile(public_id) || raise NotFoundError

    games =
      HomeLive.games()
      |> Enum.map(&Map.put(&1, :count, Map.get(profile.games, &1.id, 0)))
      |> Enum.filter(&(&1.count > 0))
      |> Enum.sort_by(& &1.count, :desc)

    {:ok,
     assign(socket,
       page_title: profile.name,
       noindex: true,
       profile: profile,
       public_id: public_id,
       games: games,
       total: profile.games |> Map.values() |> Enum.sum()
     )}
  end
end
