defmodule OctomoctoWeb.GrazeLive do
  @moduledoc """
  The settings page of Graze: the players and the visibility, with the
  public games and the results of the selected number of players.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "graze"}
  on_mount OctomoctoWeb.BestResults

  import OctomoctoWeb.SettingsComponents
  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Graze, Lobby}
  alias Octomocto.Graze.{Game, Store}
  alias OctomoctoWeb.SavedSettings

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: canonical_url(socket), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  # The Lobby tab has its own URL
  defp canonical_url(%{assigns: %{live_action: :lobby}}), do: url(~p"/graze/lobby")
  defp canonical_url(_socket), do: url(~p"/graze")

  @doc "The title and the description of the Graze pages, for search engines."
  def seo do
    [
      page_title: "Graze & Dodge: Eat the Squares, Avoid the Red Ones",
      page_description:
        "A fast arcade game in your browser: your circle eats squares to stay alive but keeps away from red ones. Play alone or with up to 3 friends in one field. Free."
    ]
  end

  # The params of the settings. Without them, the page shows the settings
  # that the user chose last.
  @settings_params ["players", "visibility"]

  def handle_params(params, _uri, socket) do
    settings =
      SavedSettings.params(socket, "graze", params, @settings_params) |> settings()

    SavedSettings.save_change(socket, "graze", settings, query(settings, []))

    filter = %{"players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       user_results: user_results(socket.assigns.current_scope, filter)
     )
     |> OctomoctoWeb.BestResults.assign_best(Graze, filter)}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A watcher came or left, see `Octomocto.Lobby.watch/3`
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watchers: Lobby.watchers(Game))}
  end

  @doc """
  Starts a game in the default settings for the number of players, and
  gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) do
    # Any player can start the next game, thus it has no creator (see
    # `Octomocto.Seats`)
    Graze.create_game(players, public, false)
  end

  def handle_event("new_game", _params, socket) do
    %{players: players, public: public} = socket.assigns.settings
    id = Graze.create_game(players, public)
    {:noreply, redirect(socket, to: ~p"/graze/#{id}")}
  end

  # One player and a public game, when the params do not say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    %{players: players, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Graze.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "Your circle follows the pointer. Move it over the squares to eat them. Each square is one point.",
      "But keep away from the red squares. One touch, and you are out.",
      "The ring around your circle is its energy. It goes down all the time, faster and faster. Each square that you eat fills part of it. When the ring is empty, you are out.",
      "More and more red squares come, and they get faster.",
      "With other players, all circles are in the same field and go through each other. The first circle to touch a square eats it.",
      "When you are out, your score stays. The game ends when all circles are out. The highest score wins.",
      "The game starts after a countdown, when all players are in."
    ]
  end

  # A small copy of the badge of the page, for a row of the lists
  defp lobby_icon(assigns) do
    ~H"""
    <div class="grid size-9 shrink-0 place-items-center rounded-xl bg-octo-indigo/10">
      <OctomoctoWeb.GameIcons.game_icon game="graze" class="size-6" />
    </div>
    """
  end

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    ~p"/graze?#{query(%{players: state.needed, public: state.public}, [])}"
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings), do: game.players_needed == settings.players

  @doc "Graze has no settings to show in a row of the lists."
  def game_summary(_game), do: nil
end
