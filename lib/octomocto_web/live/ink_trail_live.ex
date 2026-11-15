defmodule OctomoctoWeb.InkTrailLive do
  @moduledoc """
  The settings page of Ink Trail, with the ongoing public games and the
  results. Ink Trail is a single-player game: the page shows the distance at
  the start, which is the same for each new game, and the visibility. Other
  players can only watch a public game.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "ink-trail"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents,
    only: [
      setting: 1,
      setting_header: 1,
      option: 1,
      score_list: 1,
      result_row: 1,
      result_pill: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{InkTrail, Lobby}
  alias Octomocto.InkTrail.{Game, Store}
  alias OctomoctoWeb.SavedSettings

  # All results can be compared
  @filter %{"players" => 1}

  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign(
       [
         canonical_url: url(~p"/ink-trail"),
         rules: rules(),
         start_distance: Game.min_start(),
         user_results: user_results(scope)
       ] ++ seo()
     )
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))
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

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["visibility"]

  def handle_params(params, _uri, socket) do
    settings =
      SavedSettings.params(socket, "ink-trail", params, @settings_params) |> settings()

    SavedSettings.save_change(socket, "ink-trail", settings, query(settings, []))

    {:noreply, assign(socket, settings: settings)}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A watcher came or left, see `Octomocto.Lobby.watch/3`
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watchers: Lobby.watchers(Game))}
  end

  def handle_event("new_game", _params, socket) do
    id =
      InkTrail.create_game(%{
        start_distance: socket.assigns.start_distance,
        public: socket.assigns.settings.public
      })

    {:noreply, redirect(socket, to: ~p"/ink-trail/#{id}")}
  end

  # A public game, when the params do not say otherwise. The number of
  # players is for `visibility_hint/1`.
  defp settings(params), do: %{players: 1, public: params["visibility"] != "private"}

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state), do: ~p"/ink-trail?#{query(%{public: state.public}, [])}"

  # The query of the page for the settings, with some of them changed. A
  # public game has no param, so that most links stay short.
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    if settings.public, do: [], else: [visibility: "private"]
  end

  @doc "Ink Trail has no settings to show in a row of the lists."
  def game_summary(_game), do: nil

  # A small copy of the badge of the page, for a row of the lists
  defp lobby_icon(assigns) do
    ~H"""
    <div class="grid size-9 shrink-0 place-items-center rounded-xl bg-octo-indigo/10">
      <OctomoctoWeb.GameIcons.game_icon game="ink-trail" class="size-6" />
    </div>
    """
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
