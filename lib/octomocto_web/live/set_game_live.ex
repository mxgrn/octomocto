defmodule OctomoctoWeb.SetGameLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, score_list: 1, player_list: 1, format_time: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, SetGame}
  alias Octomocto.SetGame.{Game, Store}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the Set pages, for search engines."
  def seo do
    [
      page_title: "Set: Card Game of Quick Eyes",
      page_description:
        "Find 3 cards where each feature is all the same or all different. Play alone against the clock, or race up to 4 friends. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"mode" => "normal", "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       leaderboard: SetGame.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  def handle_event("new_game", _params, socket) do
    id = SetGame.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/set/#{id}")}
  end

  # One player and a public game, when the params do not say otherwise
  defp settings(params) do
    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> 1
      end

    %{players: players, public: params["visibility"] != "private"}
  end

  defp assign_lobby(socket, entries) do
    assign(socket,
      lobby: entries,
      open_games: Lobby.open_games(entries),
      ongoing_games: Lobby.ongoing_games(entries)
    )
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
      "The game ends when the deck is empty and the table has no set. Alone, find all sets as fast as you can. With other players, find the most sets."
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

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))
    query = [players: settings.players]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings), do: game.players_needed == settings.players
end
