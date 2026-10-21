defmodule OctomoctoWeb.MemoryLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [
      setting: 1,
      setting_header: 1,
      score_list: 1,
      player_list: 1,
      format_time: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Lobby, Memory}
  alias Octomocto.Memory.{Board, Game, Store, Themes}
  alias OctomoctoWeb.MemoryChannel

  def mount(params, _session, socket) do
    locale = socket.assigns.locale
    match = match(params["match"], socket)
    if connected?(socket) and !match, do: Lobby.subscribe(Game)

    if match && connected?(socket),
      do: Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(match.id))

    {:ok,
     socket
     |> assign(
       [
         canonical_url: OctomoctoWeb.Endpoint.url() <> Locale.path(locale, ~p"/memory"),
         alternate_urls: Locale.alternate_urls("memory", ~p"/memory"),
         themes: Themes.list(),
         rules: rules(),
         banner: banner(params),
         match: match
       ] ++ seo()
     )
     |> assign_lobby(Lobby.entries(Game, Store))}
  end

  @doc "The title and the description of the Memory pages, for search engines."
  def seo do
    [
      page_title: dgettext("memory", "Memory Card Game"),
      page_description:
        dgettext("memory", "Play Memory online solo or with friends. Free, instant, no sign-up.")
    ]
  end

  @doc "The message for the people who come from the links on Pairs One, the old site of the game."
  def banner(%{"utm_source" => "pairs.one"}),
    do:
      dgettext(
        "memory",
        "Pairs One is now Octomocto. Your favorite Memory game (improved!) plus more games to play."
      )

  def banner(_params), do: nil

  def handle_params(params, _uri, socket) do
    match = socket.assigns.match
    settings = params |> match_params(match) |> settings() |> match_settings(match)
    filter = %{"set" => settings.set, "cards" => settings.cards, "players" => settings.players}

    {:noreply,
     assign(socket,
       settings: settings,
       # The other language keeps the settings
       languages:
         Locale.languages("memory", socket.assigns.locale, ~p"/memory?#{query(settings, [])}"),
       sizes: Board.sizes(settings.theme, settings.set),
       leaderboard: Memory.leaderboard(filter),
       user_results: user_results(socket.assigns.current_scope, filter)
     )}
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # The score of the match shows the changes of the players
  def handle_info({:memory_state, state}, socket) do
    {:noreply, update(socket, :match, &%{&1 | state: state})}
  end

  @doc """
  Starts a game in the default settings for the number of players, and
  gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) do
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Memory.create_game()
  end

  # The next field of the match, in the same game
  def handle_event("new_game", _params, %{assigns: %{match: %{player_id: player_id}}} = socket)
      when is_binary(player_id) do
    %{match: match, settings: settings, locale: locale} = socket.assigns
    # When the settings do not change (for example, the game stopped), the
    # game page shows the end screen again
    Memory.change_settings(match.id, player_id, Map.take(settings, [:theme, :set, :cards]))
    {:noreply, redirect(socket, to: Locale.path(locale, ~p"/memory/#{match.id}"))}
  end

  def handle_event("new_game", _params, socket) do
    id = Memory.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: Locale.path(socket.assigns.locale, ~p"/memory/#{id}"))}
  end

  # The slider gives the position of the size in the list of possible sizes,
  # so that each step of the slider is a possible number of cards
  def handle_event("cards", %{"index" => index}, socket) do
    %{sizes: sizes, settings: settings, locale: locale} = socket.assigns

    case Integer.parse(index) do
      {i, ""} when i in 0..(length(sizes) - 1)//1 ->
        {:noreply,
         push_patch(socket, to: settings_path(locale, settings, cards: Enum.at(sizes, i)))}

      _ ->
        {:noreply, socket}
    end
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
        {n, ""} when n in 1..4 -> n
        _ -> 1
      end

    public = params["visibility"] != "private"

    %{theme: theme, set: set, cards: cards, players: players, public: public, match: nil}
  end

  # The match of the page (`?match=<game id>`, see `Octomocto.Memory.Game`),
  # or nil: the `:id` of the game, the `:state` that its clients see, and
  # the `:player_id` of the player who changes the settings. The token of
  # the player is in the connect params (see app.js), so the page holds the
  # seat of the player only after the connect. Before the connect, the page
  # only shows the score.
  defp match(id, socket) when is_binary(id) do
    if connected?(socket) do
      token = get_connect_params(socket)["match_token"]

      with player_id when is_binary(player_id) <- MemoryChannel.player_id(id, token),
           {:ok, state} <- Memory.edit_settings(id, player_id) do
        %{id: id, player_id: player_id, state: state}
      else
        _ -> nil
      end
    else
      case Store.read(id) do
        %{needed: needed} = state when needed > 1 ->
          %{id: id, player_id: nil, state: Game.public(state)}

        _ ->
          nil
      end
    end
  end

  defp match(_id, _socket), do: nil

  # The settings of the game are the defaults of the match page, because
  # the link to the page has only the match
  defp match_params(params, nil), do: params

  defp match_params(params, %{state: state}) do
    Map.merge(
      %{
        "theme" => state.theme,
        "set" => if(state.set == 3, do: "triplets", else: "pairs"),
        "cards" => Integer.to_string(length(state.cards))
      },
      params
    )
  end

  # A match keeps its players and its visibility
  defp match_settings(settings, nil), do: settings

  defp match_settings(settings, %{id: id, state: state}),
    do: %{settings | players: state.players_needed, public: state.public, match: id}

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Memory.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      dgettext(
        "memory",
        "Turn over 2 cards at a time (3 for triplets) to find the cards with the same image."
      ),
      dgettext(
        "memory",
        "If they match, you get a point for each card, and you go again. If not, the next player goes."
      ),
      dgettext(
        "memory",
        "Whoever has the most points wins. Alone, clear the field as fast as you can."
      )
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

  @doc "The path of this page in the language with the settings of the game in the given state."
  def settings_path(locale, state), do: settings_path(locale, state_settings(state), [])

  @doc """
  The path of the Change settings button of the game in the given state.
  With 2 or more players, the page changes the settings of the next field
  of the match (see `Octomocto.Memory.Game`). The path has only the match,
  because the settings of the game can change after the page load.
  """
  def match_path(locale, %{needed: needed} = state) when needed > 1,
    do: Locale.path(locale, ~p"/memory?#{[match: state.id]}")

  def match_path(locale, state), do: settings_path(locale, state)

  defp state_settings(state) do
    %{
      theme: state.theme,
      set: state.set,
      cards: state.size,
      players: state.needed,
      public: state.public,
      match: nil
    }
  end

  # The path of this page in the language for the settings, with some of them changed
  defp settings_path(locale, settings, changes) do
    Locale.path(locale, ~p"/memory?#{query(settings, changes)}")
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
    query = if settings.public, do: query, else: query ++ [visibility: "private"]
    if settings.match, do: query ++ [match: settings.match], else: query
  end

  # True when the open game has the same settings as the new game
  defp same_settings?(game, settings) do
    {game.settings, game.players_needed} ==
      {Map.take(settings, [:theme, :set, :cards]), settings.players}
  end

  @doc "The settings of a game in the list of public games."
  def game_summary(%{settings: settings}) do
    set =
      if settings.set == 3, do: dgettext("memory", "Triplets"), else: dgettext("memory", "Pairs")

    cards = dngettext("memory", "%{count} card", "%{count} cards", settings.cards)
    "#{theme_title(Themes.get(settings.theme))} · #{set} · #{cards}"
  end

  # The titles of the themes in `Themes`, for `mix gettext.extract`. A new
  # theme must be in the list too.
  @theme_titles [
    dgettext_noop("memory", "Sushi"),
    dgettext_noop("memory", "Food"),
    dgettext_noop("memory", "Desert"),
    dgettext_noop("memory", "Ocean"),
    dgettext_noop("memory", "Monsters"),
    dgettext_noop("memory", "Insects"),
    dgettext_noop("memory", "Eighties"),
    dgettext_noop("memory", "Spring"),
    dgettext_noop("memory", "Flowers"),
    dgettext_noop("memory", "Birds"),
    dgettext_noop("memory", "Pets"),
    dgettext_noop("memory", "Workout"),
    dgettext_noop("memory", "Animals"),
    dgettext_noop("memory", "Fairy Tales"),
    dgettext_noop("memory", "Ecology"),
    dgettext_noop("memory", "Music"),
    dgettext_noop("memory", "Halloween"),
    dgettext_noop("memory", "Flags"),
    dgettext_noop("memory", "Cats"),
    dgettext_noop("memory", "Space")
  ]

  @doc "The title of a theme in the language of the page."
  def theme_title(%{title: title}) when title in @theme_titles,
    do: Gettext.dgettext(OctomoctoWeb.Gettext, "memory", title)

  @doc "Shows the accuracy of a player or a result, for example \"92%\", or \"—\" when it has none."
  def format_accuracy(player) do
    case Memory.accuracy(player) do
      nil -> "—"
      percent -> "#{percent}%"
    end
  end

  # The possible size before (-1) or after (1) the current one, or nil
  defp step_size(sizes, cards, -1), do: sizes |> Enum.filter(&(&1 < cards)) |> List.last()
  defp step_size(sizes, cards, 1), do: Enum.find(sizes, &(&1 > cards))
end
