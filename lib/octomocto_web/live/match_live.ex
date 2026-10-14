defmodule OctomoctoWeb.MatchLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, score_list: 1, player_list: 1, format_time: 1, player_name: 1]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Match}
  alias Octomocto.Match.{Board, Game, Store, Themes}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Lobby.subscribe(Game)

    {:ok,
     socket
     |> assign([canonical_url: url(~p"/match"), themes: Themes.list(), rules: rules()] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the Match pages, for search engines."
  def seo do
    [
      page_title: "Match: Memory Card Game",
      page_description:
        "Find the matching pairs or triplets of cards. Play alone against the clock, or take turns with up to 4 friends. Free, in your browser."
    ]
  end

  def handle_params(params, _uri, socket) do
    settings = settings(params)
    filter = %{"set" => settings.set, "cards" => settings.cards, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       sizes: Board.sizes(settings.theme, settings.set),
       leaderboard: Match.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  def handle_event("new_game", _params, socket) do
    id = Match.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: ~p"/match/#{id}")}
  end

  # The first theme, pairs, one player and a public game, when the params
  # do not say otherwise. A number of cards that is not possible changes to the
  # nearest possible one.
  defp settings(params) do
    theme = if Themes.get(params["theme"] || ""), do: params["theme"], else: Themes.default()
    set = if params["set"] == "triplets", do: 3, else: 2

    cards =
      case Integer.parse(params["cards"] || "") do
        {n, ""} -> Board.nearest_size(theme, set, n)
        _ -> Board.nearest_size(theme, set, Board.default_cards(set))
      end

    players =
      case Integer.parse(params["players"] || "") do
        {n, ""} when n in 1..5 -> n
        _ -> 1
      end

    public = params["visibility"] != "private"

    %{theme: theme, set: set, cards: cards, players: players, public: public}
  end

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Match.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      "All cards are face down. Each image is on 2 cards (pairs) or 3 cards (triplets).",
      "On your turn, turn the cards face up one by one.",
      "When the cards make a set, they go off the field. You get one point for each card, and you turn more cards.",
      "When they do not make a set, the turn goes to the next player. The cards stay face up until the next player turns a card, so remember them.",
      "With other players, a player who turns no card for 15 seconds loses the turn.",
      "The clock starts with the first card and stops when the field is empty. Alone, find all sets as fast as you can. With other players, get the most points."
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

  attr :id, :string, required: true
  attr :patch, :string, default: nil, doc: "nil when the button does nothing"
  attr :icon, :string, required: true
  attr :label, :string, required: true

  # A round button that makes the number of cards smaller or larger
  defp step_button(assigns) do
    ~H"""
    <.link
      :if={@patch}
      id={@id}
      patch={@patch}
      aria-label={@label}
      class="grid size-9 place-items-center rounded-full text-base-content/70 transition hover:bg-base-100 hover:text-base-content active:scale-90"
    >
      <.icon name={@icon} class="size-4" />
    </.link>
    <span
      :if={!@patch}
      id={@id}
      aria-disabled="true"
      class="grid size-9 place-items-center rounded-full text-base-content/20"
    >
      <.icon name={@icon} class="size-4" />
    </span>
    """
  end

  # The query of the page for the settings, with some of them changed
  defp query(settings, changes) do
    settings = Map.merge(settings, Map.new(changes))

    query = [
      theme: settings.theme,
      set: if(settings.set == 3, do: "triplets", else: "pairs"),
      cards: settings.cards,
      players: settings.players
    ]

    # A public game has no param, so that most links stay short
    if settings.public, do: query, else: query ++ [visibility: "private"]
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    {game.settings, game.players_needed} ==
      {Map.take(settings, [:theme, :set, :cards]), settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}) do
    set = if settings.set == 3, do: "Triplets", else: "Pairs"
    "#{Themes.get(settings.theme).title} · #{set} · #{settings.cards} cards"
  end

  # The possible size before (-1) or after (1) the current one, or nil
  defp step_size(sizes, cards, -1), do: sizes |> Enum.filter(&(&1 < cards)) |> List.last()
  defp step_size(sizes, cards, 1), do: Enum.find(sizes, &(&1 > cards))
end
