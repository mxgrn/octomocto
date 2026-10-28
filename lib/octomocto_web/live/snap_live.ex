defmodule OctomoctoWeb.SnapLive do
  @moduledoc """
  The settings page of Snap, with the results. Snap is a single-player
  game, so the page has no lists of public games.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "snap"}

  import OctomoctoWeb.SettingsComponents,
    only: [setting: 1, option: 1, score_list: 1, result_row: 1, result_pill: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.Snap

  def mount(_params, _session, socket) do
    {:ok, assign(socket, [canonical_url: url(~p"/snap"), rules: rules()] ++ seo())}
  end

  @doc "The title and the description of the Snap pages, for search engines."
  def seo do
    [
      page_title: "Snap: a Lumosity Speed Match-Like Brain Game Online",
      page_description:
        "A free brain game like Speed Match from Lumosity: is the new card the same as the card before it? Answer as fast as you can for 45 seconds. No sign-up."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"back" => settings.back, "players" => 1}

    {:noreply,
     assign(socket,
       settings: settings,
       best_results: Snap.best_results(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_event("new_game", _params, socket) do
    id = Snap.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/snap/#{id}")}
  end

  # The previous card, when the params do not say otherwise
  defp settings(params) do
    back =
      case Integer.parse(params["back"] || "") do
        {n, ""} when n in 1..3 -> n
        _ -> 1
      end

    %{back: back}
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Snap.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "Cards with shapes come one by one. Say if the shape on the new card is the same as the shape on the card before it.",
      "Click Yes or No, or press the right arrow key for Yes and the left arrow key for No.",
      "With Cards back set to 2 or 3, compare the new card with the card 2 or 3 places before it. The first cards only show you what to remember.",
      "Each correct answer gives points. Each 4 correct answers in a row make the multiplier larger, up to ×5. A wrong answer sets it back to ×1.",
      "You have 45 seconds. Be fast, but be careful!",
      "Snap is a Speed Match-like game. Lumosity and Speed Match are trademarks of Lumos Labs, Inc. Octomocto is not affiliated with Lumos Labs."
    ]
  end

  defp back_hint(1), do: "Is the new card the same as the card before it?"
  defp back_hint(n), do: "Is the new card the same as the card #{n} places before it?"

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state), do: ~p"/snap?#{query(%{back: state.back})}"

  # The previous card has no param, so that most links stay short
  defp query(%{back: 1}), do: []
  defp query(%{back: back}), do: [back: back]

  defp accuracy(%{correct: correct, wrong: wrong}) when correct + wrong > 0,
    do: "#{round(100 * correct / (correct + wrong))}%"

  defp accuracy(_result), do: "–"
end
