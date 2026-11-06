defmodule OctomoctoWeb.AfterglowLive do
  @moduledoc """
  The settings page of Afterglow, with the results. Afterglow is a
  single-player game without settings, so the page has no lists of public
  games. It shows the tiles of the first round instead: the tiles of the
  last round of the last game of the user or the guest.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "afterglow"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents,
    only: [setting_header: 1, score_list: 1, result_row: 1, result_pill: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.Afterglow
  alias Octomocto.Afterglow.Game

  # All results can be compared
  @filter %{"players" => 1}

  def mount(_params, session, socket) do
    scope = socket.assigns.current_scope

    last_level =
      Afterglow.last_level(
        scope && scope.user.id,
        OctomoctoWeb.GuestName.id_from_session(session)
      )

    level = last_level || Game.min_level()
    side = Game.size(level)

    {:ok,
     assign(
       socket,
       [
         canonical_url: url(~p"/afterglow"),
         rules: rules(),
         start_level: level,
         first_game: last_level == nil,
         # A small grid with the tiles of the first round, lit at random
         preview: %{side: side, lit: MapSet.new(Enum.take_random(0..(side * side - 1), level))},
         user_results: user_results(scope)
       ] ++ seo()
     )
     |> OctomoctoWeb.BestResults.assign_best(Afterglow, @filter)}
  end

  @doc "The title and the description of the Afterglow pages, for search engines."
  def seo do
    [
      page_title: "Afterglow: a Memory Matrix-Like Brain Game Online",
      page_description:
        "A free brain game like Memory Matrix from Lumosity: tiles light up for a moment, then click the tiles that were lit. 10 rounds that grow with you. No sign-up."
    ]
  end

  def handle_event("new_game", _params, socket) do
    id = Afterglow.create_game(%{start_level: socket.assigns.start_level})
    {:noreply, redirect(socket, to: ~p"/afterglow/#{id}")}
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope), do: Afterglow.user_results(scope, @filter)
  defp user_results(nil), do: nil

  defp rules do
    [
      "Some tiles of the grid light up for a moment. Remember where they are.",
      "When the tiles go out, click all tiles that were lit, in any order.",
      "A wrong tile ends the round. After a fully correct round, the next round has one tile more, else it has one tile less. The grid grows with the tiles.",
      "Each correct tile gives points times the number of tiles in the round.",
      "A game has 10 rounds. Your next game starts with the tiles of your last round.",
      "Afterglow is a Memory Matrix-like game. Lumosity and Memory Matrix are trademarks of Lumos Labs, Inc. Octomocto is not affiliated with Lumos Labs."
    ]
  end
end
