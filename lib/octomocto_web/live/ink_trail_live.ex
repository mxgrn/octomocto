defmodule OctomoctoWeb.InkTrailLive do
  @moduledoc """
  The settings page of Ink Trail, with the results. Ink Trail is a
  single-player game with no settings: the page shows the distance at the
  start, where the last game of the user or the guest ended (see
  `Octomocto.InkTrail.start_distance/2`).
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "ink-trail"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents,
    only: [setting_header: 1, score_list: 1, result_row: 1, result_pill: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.InkTrail
  alias Octomocto.InkTrail.Game

  # All results can be compared
  @filter %{"players" => 1}

  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope
    guest_id = OctomoctoWeb.GuestName.id_from_session(session)
    distance = InkTrail.start_distance(scope && scope.user.id, guest_id)

    {:ok,
     socket
     |> assign(
       [
         canonical_url: url(~p"/ink-trail"),
         rules: rules(),
         start_distance: distance,
         first_game: distance == Game.min_start(),
         user_results: user_results(scope)
       ] ++ seo()
     )
     |> OctomoctoWeb.BestResults.assign_best(InkTrail, @filter)}
  end

  @doc "The title and the description of the Ink Trail pages, for search engines."
  def seo do
    [
      page_title: "Ink Trail: a Follow That Frog-Like Brain Game Online",
      page_description:
        "A free brain game like Follow That Frog from Lumosity: follow the path of an octopus from cave to cave, some jets behind it. No sign-up."
    ]
  end

  def handle_event("new_game", _params, socket) do
    id = InkTrail.create_game(%{start_distance: socket.assigns.start_distance})
    {:noreply, redirect(socket, to: ~p"/ink-trail/#{id}")}
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope), do: InkTrail.user_results(scope, @filter)
  defp user_results(nil), do: nil

  defp rules do
    [
      "A leader octopus jets from cave to cave. Your octopus follows the same path, some jets behind it.",
      "Click the cave where your octopus must go next: the cave where the leader was that many jets ago. Then the leader jets again.",
      "You see only the two octopi, so remember the path between them.",
      "Each 5 correct clicks in a row put your octopus one jet further behind. A wrong click brings it one jet nearer, but never nearer than 3 jets.",
      "Each correct click gives points times the distance. The game ends after 40 correct clicks. Your next game starts at the distance where this one ended.",
      "Ink Trail is a Follow That Frog-like game. Lumosity and Follow That Frog are trademarks of Lumos Labs, Inc. Octomocto is not affiliated with Lumos Labs."
    ]
  end
end
