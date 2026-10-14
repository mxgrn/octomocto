defmodule OctomoctoWeb.MatchLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, score_list: 1, player_list: 1, format_time: 1, player_name: 1]

  alias Octomocto.Match
  alias Octomocto.Match.{Board, Game, Themes}

  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.lobby_topic())

    {:ok, socket |> assign([themes: Themes.list()] ++ seo()) |> assign_lobby(Match.lobby())}
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

  def handle_info({:lobby_changed, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Match.put_lobby_entry(socket.assigns.lobby, id, entry))}
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
    assign(socket,
      lobby: entries,
      open_games: Match.open_games(entries),
      ongoing_games: Match.ongoing_games(entries)
    )
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Match.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  attr :games, :list, required: true, doc: "see `Octomocto.Match.open_games/1`"
  attr :settings, :map, required: true, doc: "the settings of the new game"

  # The public games that wait for players. A game with the same settings
  # as the new game has a green background.
  defp open_games(assigns) do
    ~H"""
    <section
      id="open-games"
      class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10"
    >
      <h3 class="mb-3 flex items-center gap-2 font-semibold">
        <.icon name="hero-user-group" class="size-4 text-sky-600" /> Open games
      </h3>
      <p
        :if={@games == []}
        id="open-games-empty"
        class="py-2 text-center text-sm text-base-content/50"
      >
        No open games. Make a public one.
      </p>
      <ul :if={@games != []} id="open-games-list" class="-mx-2 space-y-1">
        <li
          :for={game <- @games}
          id={"open-game-#{game.id}"}
          class={[
            "flex items-center gap-3 rounded-xl px-2 py-2 transition-colors",
            if(same_settings?(game, @settings),
              do: "bg-emerald-50 dark:bg-emerald-500/10",
              else: "hover:bg-base-200/60"
            )
          ]}
        >
          <img src={~p"/images/match/#{game.theme}/1.svg"} alt="" class="size-9 shrink-0" />
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium">{game_summary(game)}</p>
            <p class="flex flex-wrap gap-x-2.5 text-xs text-base-content/70">
              <span :for={player <- game.players} class="flex items-center gap-1">
                <span class={[
                  "size-1.5 rounded-full transition-colors",
                  if(player.away, do: "bg-base-content/25", else: "bg-emerald-500")
                ]} />
                {lobby_name(player)}
              </span>
            </p>
          </div>
          <span class="shrink-0 text-xs tabular-nums text-base-content/50">
            {game.players_needed - game.seats_left} of {game.players_needed}
          </span>
          <.link
            id={"join-#{game.id}"}
            href={~p"/match/#{game.id}"}
            class="shrink-0 rounded-full bg-sky-600 px-4 py-1.5 text-sm font-medium text-white shadow-sm transition hover:-translate-y-0.5 hover:bg-sky-500 active:translate-y-0"
          >
            Join
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  attr :games, :list, required: true, doc: "see `Octomocto.Match.ongoing_games/1`"

  # The public games that have started. The player of the turn is in bold.
  defp ongoing_games(assigns) do
    ~H"""
    <section
      id="ongoing-games"
      class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10"
    >
      <h3 class="mb-3 flex items-center gap-2 font-semibold">
        <.icon name="hero-play-circle" class="size-4 text-sky-600" /> Ongoing games
      </h3>
      <p
        :if={@games == []}
        id="ongoing-games-empty"
        class="py-2 text-center text-sm text-base-content/50"
      >
        No games now.
      </p>
      <ul :if={@games != []} id="ongoing-games-list" class="-mx-2 space-y-1">
        <li
          :for={game <- @games}
          id={"ongoing-game-#{game.id}"}
          class="flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-base-200/60"
        >
          <img src={~p"/images/match/#{game.theme}/1.svg"} alt="" class="size-9 shrink-0" />
          <div class="min-w-0 flex-1">
            <p class="flex items-center gap-2 text-sm font-medium">
              <span class="truncate">{game_summary(game)}</span>
              <span
                :if={game.finished}
                class="shrink-0 rounded-full bg-amber-500/10 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400"
              >
                Finished
              </span>
            </p>
            <p class="flex flex-wrap gap-x-2.5 text-xs text-base-content/70">
              <span :for={player <- game.players} class="flex items-center gap-1">
                <span class={[
                  "size-1.5 rounded-full transition-colors",
                  if(player.away, do: "bg-base-content/25", else: "bg-emerald-500")
                ]} />
                <span class={[
                  (player.turn and not game.finished) && "font-semibold text-base-content"
                ]}>
                  {lobby_name(player)}
                </span>
                <span class="tabular-nums text-base-content/50">{player.score}</span>
              </span>
            </p>
          </div>
          <.link
            id={"watch-#{game.id}"}
            href={~p"/match/#{game.id}?watch=1"}
            class="shrink-0 rounded-full px-4 py-1.5 text-sm font-medium text-sky-700 ring-1 ring-sky-600/30 transition hover:-translate-y-0.5 hover:bg-sky-50 active:translate-y-0 dark:text-sky-400 dark:hover:bg-sky-500/10"
          >
            Watch
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  # The rules of the game in a pop-up. It opens and closes in the browser,
  # with no call to the server.
  defp rules(assigns) do
    ~H"""
    <div
      id="rules"
      class="fixed inset-0 z-50 hidden"
      role="dialog"
      aria-modal="true"
      aria-labelledby="rules-title"
      phx-window-keydown={hide_rules()}
      phx-key="Escape"
    >
      <div id="rules-backdrop" class="absolute inset-0 hidden bg-black/40 backdrop-blur-sm" />
      <div class="relative flex min-h-full items-center justify-center p-4">
        <div
          id="rules-panel"
          phx-click-away={hide_rules()}
          class="hidden w-full max-w-lg rounded-2xl bg-base-100 p-6 shadow-xl ring-1 ring-base-content/10"
        >
          <div class="mb-4 flex items-center justify-between gap-3">
            <h2 id="rules-title" class="text-xl font-semibold">How to play</h2>
            <button
              id="rules-close"
              type="button"
              phx-click={hide_rules()}
              aria-label="Close"
              class="grid size-9 cursor-pointer place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <ul class="space-y-2.5 text-base-content/80">
            <li :for={rule <- rules_text()} class="flex gap-3">
              <span class="mt-2.5 size-1.5 shrink-0 rounded-full bg-sky-500" />
              <span>{rule}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp rules_text do
    [
      "All cards are face down. Each image is on 2 cards (pairs) or 3 cards (triplets).",
      "On your turn, turn the cards face up one by one.",
      "When the cards make a set, they go off the field. You get one point for each card, and you turn more cards.",
      "When they do not make a set, the turn goes to the next player. The cards stay face up until the next player turns a card, so remember them.",
      "With more than 2 players, a player who turns no card for 15 seconds loses the turn.",
      "The clock starts with the first card and stops when the field is empty. Alone, find all sets as fast as you can. With other players, get the most points."
    ]
  end

  defp show_rules do
    JS.show(to: "#rules")
    |> JS.show(
      to: "#rules-backdrop",
      time: 200,
      transition: {"transition-opacity ease-out duration-200", "opacity-0", "opacity-100"}
    )
    |> show("#rules-panel")
    |> JS.focus_first(to: "#rules-panel")
  end

  defp hide_rules do
    hide("#rules-panel")
    |> JS.hide(
      to: "#rules-backdrop",
      time: 200,
      transition: {"transition-opacity ease-in duration-200", "opacity-100", "opacity-0"}
    )
    # Waits for the panel and the backdrop to go
    |> JS.hide(to: "#rules", time: 200, transition: {"duration-200", "", ""})
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
          do: "bg-sky-600 text-white shadow-sm",
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
    {game.theme, game.set, game.cards, game.players_needed} ==
      {settings.theme, settings.set, settings.cards, settings.players}
  end

  defp game_summary(game) do
    set = if game.set == 3, do: "Triplets", else: "Pairs"
    "#{Themes.get(game.theme).title} · #{set} · #{game.cards} cards"
  end

  # A guest has the name of its color
  defp lobby_name(%{name: nil, color_name: color_name}), do: String.capitalize(color_name)
  defp lobby_name(%{name: name}), do: name

  # The possible size before (-1) or after (1) the current one, or nil
  defp step_size(sizes, cards, -1), do: sizes |> Enum.filter(&(&1 < cards)) |> List.last()
  defp step_size(sizes, cards, 1), do: Enum.find(sizes, &(&1 > cards))
end
