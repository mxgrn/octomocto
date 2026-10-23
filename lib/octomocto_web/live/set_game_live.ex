defmodule OctomoctoWeb.SetGameLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, "set"}

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [
      setting: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      format_time: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, SetGame}
  alias Octomocto.SetGame.{Deck, Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/set"), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  @doc "The title and the description of the Set pages, for search engines."
  def seo do
    [
      page_title: "Set: Card Game of Quick Eyes",
      page_description:
        "Find 3 cards where each feature is all the same or all different. Play solo against the clock or race up to 4 friends. Free."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"mode" => settings.mode, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       best_results: SetGame.best_results(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
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
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> SetGame.create_game()
  end

  def handle_event("new_game", _params, socket) do
    id = SetGame.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/set/#{id}")}
  end

  # One player, the normal mode and a public game, when the params do not
  # say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    mode = if params["mode"] in Deck.modes(), do: params["mode"], else: "normal"

    %{players: players, mode: mode, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: SetGame.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "Each card has 4 features: the number of shapes (1, 2 or 3), the shape (diamond, oval or squiggle), the shading (solid, striped or open) and the color (red, green or purple).",
      "A set is 3 cards where each feature is the same on all 3 cards, or different on all 3 cards.",
      "For example, 1 red solid diamond, 2 red striped ovals and 3 red open squiggles are a set: the color is the same on all cards, and the number, the shape and the shading are different on all cards.",
      "Click 3 cards to claim a set. A correct set goes off the table, and new cards take its place. A wrong set changes nothing.",
      "When the table has no set, 3 more cards come from the deck.",
      "All players look at the same table. The first player who claims a set gets the point.",
      "The game ends when the deck is empty and the table has no set. Alone, find all sets as fast as you can. With other players, find the most sets.",
      "In the easy mode, the deck has only the 27 solid cards."
    ]
  end

  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :selected, :boolean, required: true
  slot :inner_block, required: true

  defp option(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      class={[
        "min-w-10 rounded-full px-4 py-1.5 text-sm font-medium transition",
        if(@selected,
          do: "bg-octo-indigo text-white shadow-sm",
          else: "text-base-content/70 hover:bg-base-100 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :class, :string, default: nil

  # A small card with 3 purple diamonds, the icon of the game
  defp card_icon(assigns) do
    ~H"""
    <svg viewBox="0 0 48 32" class={@class} aria-hidden="true">
      <rect
        x="1"
        y="1"
        width="46"
        height="30"
        rx="5"
        class="fill-white stroke-base-content/15"
        stroke-width="1.5"
      />
      <path
        :for={x <- [14, 24, 34]}
        d={"M#{x} 7 L#{x + 4.5} 16 L#{x} 25 L#{x - 4.5} 16 Z"}
        fill="#7c3aed"
      />
    </svg>
    """
  end

  @doc "The path of this page with the settings of the game in the given state."
  def settings_path(state) do
    settings = %{
      players: state.needed,
      mode: Map.get(state, :mode, "normal"),
      public: state.public
    }

    ~p"/set?#{query(settings, [])}"
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players, mode: settings.mode]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    game.players_needed == settings.players and game.settings.mode == settings.mode
  end

  defp mode_hint("easy"), do: "27 cards, all solid."
  defp mode_hint("normal"), do: "All 81 cards."

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: %{mode: "easy"}}), do: "Easy"
  def game_summary(_game), do: "Normal"
end
