defmodule OctomoctoWeb.MemoryLive do
  use OctomoctoWeb, :live_view

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [
      setting: 1,
      setting_header: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      format_time: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents

  alias Octomocto.{Accounts, Lobby, Memory}
  alias Octomocto.Memory.{Board, Campaign, Game, Store, Themes}
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

  # The params of the Free play tab. Without them, a signed-in user goes to
  # the tab that the user used last.
  @settings_params ["theme", "set", "cards", "players", "visibility", "match"]

  def handle_params(params, _uri, %{assigns: %{live_action: :campaign}} = socket) do
    locale = socket.assigns.locale

    {:noreply,
     socket
     |> remember_tab("campaign")
     |> assign(
       settings: settings(%{}),
       canonical_url: OctomoctoWeb.Endpoint.url() <> Locale.path(locale, ~p"/memory/campaign"),
       alternate_urls: Locale.alternate_urls("memory", ~p"/memory/campaign"),
       languages: Locale.languages("memory", locale, ~p"/memory/campaign")
     )
     |> assign_campaign(params)}
  end

  def handle_params(params, _uri, socket) do
    %{current_scope: scope, locale: locale} = socket.assigns

    if campaign_tab?(scope) and not Enum.any?(@settings_params, &Map.has_key?(params, &1)) do
      {:noreply, push_patch(socket, to: Locale.path(locale, ~p"/memory/campaign"))}
    else
      {:noreply, socket |> remember_tab("free") |> assign_free_play(params)}
    end
  end

  defp campaign_tab?(%{user: %{memory_tab: "campaign"}}), do: true
  defp campaign_tab?(_scope), do: false

  # Saves the tab for a signed-in user, once the page is connected
  defp remember_tab(%{assigns: %{current_scope: %{user: user} = scope}} = socket, tab) do
    if connected?(socket) and (user.memory_tab || "free") != tab do
      assign(socket, current_scope: %{scope | user: Accounts.update_user_memory_tab(user, tab)})
    else
      socket
    end
  end

  defp remember_tab(socket, _tab), do: socket

  defp assign_free_play(socket, params) do
    match = socket.assigns.match
    settings = params |> match_params(match) |> settings() |> match_settings(match)
    filter = %{"set" => settings.set, "cards" => settings.cards, "players" => settings.players}

    assign(socket,
      settings: settings,
      canonical_url:
        OctomoctoWeb.Endpoint.url() <> Locale.path(socket.assigns.locale, ~p"/memory"),
      alternate_urls: Locale.alternate_urls("memory", ~p"/memory"),
      # The other language keeps the settings
      languages:
        Locale.languages("memory", socket.assigns.locale, ~p"/memory?#{query(settings, [])}"),
      sizes: Board.sizes(settings.theme, settings.set),
      leaderboard: Memory.leaderboard(filter),
      user_results: user_results(socket.assigns.current_scope, filter)
    )
  end

  # The levels of the campaign with the progress of the user, the selected
  # level (`?level=`, else the next level to play) and the theme choice
  # (`?theme=`, else "random"). A guest sees the levels of a new player.
  defp assign_campaign(socket, params) do
    progress =
      case socket.assigns.current_scope do
        %{user: user} -> Campaign.progress(user.id)
        nil -> %{}
      end

    highest = Campaign.highest(progress)

    levels =
      Enum.map(Campaign.levels(), fn level ->
        run = progress[level.level]

        status =
          cond do
            run && run.completed_at -> :done
            level.level == highest + 1 -> :current
            true -> :locked
          end

        Map.merge(level, %{status: status, cleared: if(run, do: run.best_cleared, else: 0)})
      end)

    selected =
      case Integer.parse(params["level"] || "") do
        {n, ""} when n in 1..length(levels)//1 -> n
        _ -> min(highest + 1, length(levels))
      end

    theme = if Themes.get(params["theme"] || ""), do: params["theme"], else: "random"

    assign(socket,
      campaign: %{
        levels: levels,
        selected: Enum.at(levels, selected - 1),
        highest: highest,
        theme: theme,
        leaderboard: Campaign.leaderboard()
      }
    )
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

  def handle_event(
        "play_level",
        %{"level" => level},
        %{assigns: %{current_scope: %{user: user}}} = socket
      ) do
    with {n, ""} <- Integer.parse(level),
         {:ok, id} <- Campaign.start(user.id, n, socket.assigns.campaign.theme) do
      {:noreply, redirect(socket, to: Locale.path(socket.assigns.locale, ~p"/memory/#{id}"))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("play_level", _params, socket), do: {:noreply, socket}

  def handle_event("campaign_theme", %{"theme" => theme}, socket) do
    %{locale: locale, campaign: campaign} = socket.assigns
    {:noreply, push_patch(socket, to: campaign_path(locale, campaign.selected.level, theme))}
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

  attr :theme, :string, required: true, doc: "nil in the results from before the theme"

  # The cover card of the theme of a result, as in the list of public games
  defp result_theme(assigns) do
    assigns = assign(assigns, :theme, Themes.get(assigns.theme))

    ~H"""
    <img
      :if={@theme}
      src={~p"/images/memory/#{@theme.name}/#{Themes.cover(@theme.name)}"}
      alt=""
      title={theme_title(@theme)}
      class="size-9 shrink-0"
    />
    <span
      :if={!@theme}
      class="grid size-9 shrink-0 place-items-center rounded-lg bg-base-200 text-base-content/30"
    >
      <.icon name="hero-square-2-stack" class="size-5" />
    </span>
    """
  end

  @doc """
  The path of this page in the language with the settings of the game in
  the given state. For a game of the campaign, the map with its level.
  """
  def settings_path(locale, %{campaign: %{level: level, theme: theme}}),
    do: campaign_path(locale, level, theme)

  def settings_path(locale, state), do: settings_path(locale, state_settings(state), [])

  @doc "The path of the Campaign tab with the level and the theme choice selected."
  def campaign_path(locale, level, theme) do
    query = if theme == "random", do: [level: level], else: [level: level, theme: theme]
    Locale.path(locale, ~p"/memory/campaign?#{query}")
  end

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

  @doc """
  The settings of a game in the list of public games. In a campaign game,
  the word "Campaign" is a link to the campaign page.
  """
  def game_summary(%{id: id, settings: settings}) do
    set =
      if settings.set == 3, do: dgettext("memory", "Triplets"), else: dgettext("memory", "Pairs")

    cards = dngettext("memory", "%{count} card", "%{count} cards", settings.cards)
    summary = "#{theme_title(Themes.get(settings.theme))} · #{set} · #{cards}"

    case settings do
      %{campaign: level} ->
        assigns = %{
          id: id,
          level: dgettext("memory", "Level %{level}", level: level),
          summary: summary,
          path: Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/memory/campaign")
        }

        ~H"""
        <.link
          id={"lobby-campaign-#{@id}"}
          navigate={@path}
          class="text-octo-indigo transition hover:underline dark:text-octo-indigo-light"
        >{dgettext("memory", "Campaign")}</.link>
        · {@level} · {@summary}
        """

      _ ->
        summary
    end
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

  attr :tab, :atom, required: true, doc: ":free or :campaign"
  attr :free_path, :string, required: true
  attr :locale, :string, required: true

  # The Free play and Campaign tabs, as the options of a setting
  defp mode_tabs(assigns) do
    ~H"""
    <nav id="memory-tabs" class="flex justify-center">
      <div class="flex gap-1 rounded-full bg-base-200 p-1">
        <.option id="tab-free" patch={@free_path} selected={@tab == :free}>
          {dgettext("memory", "Free play")}
        </.option>
        <%!-- In the brand orange, so that it stands out from the indigo of the selected tab --%>
        <span class="relative">
          <.option
            id="tab-campaign"
            patch={Locale.path(@locale, ~p"/memory/campaign")}
            selected={@tab == :campaign}
          >
            {dgettext("memory", "Campaign")}
          </.option>
          <span
            id="tab-campaign-new"
            class="pointer-events-none absolute -top-2.5 -right-2.5 z-10 rounded-full bg-octo-orange px-1.5 py-0.5 text-[10px] leading-none font-semibold tracking-wide text-white uppercase shadow-sm"
          >
            {dgettext("memory", "New")}
          </span>
        </span>
      </div>
    </nav>
    """
  end

  # The height of a row of the map, and the place of the first row
  @map_row_height 104
  @map_top 40

  attr :levels, :list, required: true
  attr :selected, :integer, required: true
  attr :theme, :string, required: true
  attr :locale, :string, required: true

  # The levels on a winding path. Each level is a circle with a ring that
  # shows the best run. The circles are HTML, with a place in percent of the
  # width, so that they move with the width but keep their size. The lines
  # between them are borders: a solid line after a done level, else a
  # dashed one. A narrow map has 3 levels in a row, a wider map 4 (a
  # container query, so it depends on the width of the map, not of the
  # screen).
  defp campaign_map(assigns) do
    ~H"""
    <div id="campaign-map" class="@container w-full">
      <.map_rows
        :for={columns <- [3, 4]}
        columns={columns}
        levels={@levels}
        selected={@selected}
        theme={@theme}
        locale={@locale}
        class={if(columns == 3, do: "@sm:hidden", else: "hidden @sm:block")}
      />
    </div>
    """
  end

  attr :columns, :integer, required: true
  attr :levels, :list, required: true
  attr :selected, :integer, required: true
  attr :theme, :string, required: true
  attr :locale, :string, required: true
  attr :class, :string, required: true

  defp map_rows(assigns) do
    %{columns: columns, levels: levels} = assigns

    place = fn index ->
      row = div(index, columns)
      column = rem(index, columns)
      # Odd rows go from right to left
      column = if rem(row, 2) == 1, do: columns - 1 - column, else: column
      {column * 100 / (columns - 1), @map_top + row * @map_row_height}
    end

    lines =
      for {level, index} <- Enum.with_index(Enum.drop(levels, -1)) do
        {x1, y1} = place.(index)
        {x2, y2} = place.(index + 1)
        done = level.status == :done

        if y1 == y2,
          do: %{kind: :line, left: min(x1, x2), width: abs(x1 - x2), top: y1, done: done},
          else: %{kind: :turn, side: if(x1 > 50, do: :right, else: :left), top: y1, done: done}
      end

    assigns =
      assign(assigns,
        nodes: Enum.with_index(levels, &{&1, place.(&2)}),
        lines: lines,
        row_height: @map_row_height,
        height: div(length(levels) + columns - 1, columns) * @map_row_height
      )

    ~H"""
    <div class={@class}>
      <div class="relative mx-10" style={"height: #{@height}px"}>
        <div
          :for={line <- @lines}
          class={[
            "absolute",
            line.kind == :line && "h-0",
            line.kind == :turn && "w-8",
            line.kind == :turn && line.side == :right && "left-full rounded-r-full border-l-0!",
            line.kind == :turn && line.side == :left && "right-full rounded-l-full border-r-0!",
            if(line.done,
              do: "-mt-0.5 border-4 border-octo-indigo",
              else: "-mt-px border-2 border-dashed border-base-content/20"
            ),
            line.kind == :line && "border-x-0! border-b-0!"
          ]}
          style={
            if(line.kind == :line,
              do: "left: #{line.left}%; width: #{line.width}%; top: #{line.top}px",
              else: "top: #{line.top}px; height: #{@row_height}px"
            )
          }
        />
        <.level_node
          :for={{level, {x, y}} <- @nodes}
          id={"level-#{@columns}-#{level.level}"}
          level={level}
          selected={level.level == @selected}
          patch={campaign_path(@locale, level.level, @theme)}
          style={"left: #{x}%; top: #{y}px"}
        />
      </div>
    </div>
    """
  end

  # The length of the ring around a level
  @ring_length 2 * :math.pi() * 29

  attr :id, :string, required: true
  attr :level, :map, required: true
  attr :selected, :boolean, required: true
  attr :patch, :string, required: true
  attr :style, :string, required: true

  defp level_node(assigns) do
    level = assigns.level

    assigns =
      assign(assigns, percent: div(100 * level.cleared, level.cards), ring_length: @ring_length)

    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      aria-label={dgettext("memory", "Level %{level}", level: @level.level)}
      class="group absolute flex w-20 -translate-x-1/2 -translate-y-8 flex-col items-center"
      style={@style}
    >
      <span class="relative grid size-16 place-items-center transition group-hover:scale-105">
        <svg viewBox="0 0 64 64" class="absolute inset-0" aria-hidden="true">
          <circle
            :if={@level.status != :locked}
            cx="32"
            cy="32"
            r="29"
            fill="none"
            stroke-width="4"
            class="stroke-base-content/10"
          />
          <circle
            :if={@level.status != :locked and @percent > 0}
            cx="32"
            cy="32"
            r="29"
            fill="none"
            stroke-width="4"
            stroke-linecap={if(@percent < 100, do: "round", else: "butt")}
            stroke-dasharray={"#{@ring_length * @percent / 100} #{@ring_length}"}
            transform="rotate(-90 32 32)"
            class="stroke-octo-indigo"
          />
          <circle
            cx="32"
            cy="32"
            r="23"
            stroke-width={if(@selected, do: 3, else: 1.5)}
            class={
              case @level.status do
                :done -> "fill-octo-indigo stroke-octo-indigo"
                :current -> "fill-base-100 stroke-octo-indigo"
                :locked -> "fill-base-200 stroke-base-content/15"
              end
            }
          />
        </svg>
        <span class={[
          "relative flex flex-col items-center leading-none",
          @level.status == :done && "text-white",
          @level.status == :current && "text-octo-indigo",
          @level.status == :locked && "text-base-content/40"
        ]}>
          <span class={[
            "font-semibold tabular-nums",
            if(@level.status == :locked, do: "text-sm", else: "text-lg")
          ]}>
            {@level.level}
          </span>
          <.icon :if={@level.status == :locked} name="hero-lock-closed-mini" class="mt-0.5 size-3" />
          <span
            :if={@level.status == :current and @percent > 0}
            class="mt-0.5 text-[10px] tabular-nums text-base-content/60"
          >
            {@percent}%
          </span>
        </span>
        <span
          :if={@level.set == 3}
          title={dgettext("memory", "Triplets")}
          class={[
            "absolute -top-0.5 -right-0.5 grid size-5 place-items-center rounded-full bg-base-100 text-[11px] font-semibold ring-1",
            if(@level.status == :locked,
              do: "text-base-content/40 ring-base-content/15",
              else: "text-octo-indigo ring-octo-indigo"
            )
          ]}
        >
          3
        </span>
      </span>
      <span class="mt-0.5 text-xs whitespace-nowrap text-base-content/60">
        {dngettext("memory", "%{count} card", "%{count} cards", @level.cards)}
      </span>
    </.link>
    """
  end

  attr :level, :map, required: true
  attr :theme, :string, required: true
  attr :highest, :integer, required: true

  # The selected level: its grid, the theme choice and the Play button. It
  # stays at the bottom of the screen while the map does not fit, so that
  # the Play button is always in view.
  defp level_card(assigns) do
    {columns, rows, gaps} = preview_layout(assigns.level.cards)

    themes =
      Enum.map(Campaign.themes(assigns.level), &{theme_title(&1), &1.name})
      |> Enum.sort()

    assigns =
      assign(assigns,
        columns: columns,
        places: columns * rows,
        gaps: gaps,
        theme_options: [{dgettext("memory", "Random"), "random"} | themes],
        theme_value:
          if(Enum.any?(themes, &(elem(&1, 1) == assigns.theme)),
            do: assigns.theme,
            else: "random"
          )
      )

    ~H"""
    <div
      id="level-card"
      class="sticky bottom-3 z-10 flex w-full flex-wrap items-center gap-x-5 gap-y-4 rounded-2xl bg-base-100 p-5 text-left shadow-lg ring-1 ring-base-content/10"
    >
      <div
        class="grid shrink-0 gap-0.5"
        style={"grid-template-columns: repeat(#{@columns}, 0.375rem)"}
        aria-hidden="true"
      >
        <span
          :for={place <- 1..@places}
          class={[
            "h-2 rounded-[2px]",
            (@gaps > 0 and place == div(@places, 2) + 1) && "invisible",
            if(@level.status == :locked, do: "bg-base-content/15", else: "bg-octo-indigo")
          ]}
        />
      </div>
      <div class="min-w-40 flex-1">
        <h3 id="level-card-title" class="flex items-center gap-1.5 font-semibold">
          {dgettext("memory", "Level %{level}", level: @level.level)}
          <.icon
            :if={@level.status == :done}
            name="hero-check-circle-mini"
            class="size-5 text-octo-indigo"
          />
        </h3>
        <p class="text-sm text-base-content/60">
          {dngettext("memory", "%{count} card", "%{count} cards", @level.cards)} · {if @level.set == 2,
            do: dgettext("memory", "Pairs"),
            else: dgettext("memory", "Triplets")}
          <span :if={@level.status == :current and @level.cleared > 0}>
            · {dgettext("memory", "best: %{cleared} of %{cards} cleared",
              cleared: @level.cleared,
              cards: @level.cards
            )}
          </span>
        </p>
      </div>
      <%= if @level.status == :locked do %>
        <p id="level-locked" class="flex items-center gap-1.5 text-sm text-base-content/60">
          <.icon name="hero-lock-closed-mini" class="size-4" />
          {dgettext("memory", "Finish level %{level} with no errors first.", level: @highest + 1)}
        </p>
      <% else %>
        <div class="flex flex-wrap items-center gap-3">
          <.form for={%{}} id="campaign-theme-form" phx-change="campaign_theme">
            <label class="flex items-center gap-2 text-sm text-base-content/60">
              {dgettext("memory", "Theme")}
              <select
                id="campaign-theme"
                name="theme"
                class="cursor-pointer rounded-full border-0 bg-base-200 py-1.5 pr-8 pl-3 text-sm font-medium text-base-content ring-1 ring-base-content/10 transition hover:ring-base-content/20 focus:ring-2 focus:ring-octo-indigo focus:outline-none"
              >
                {Phoenix.HTML.Form.options_for_select(@theme_options, @theme_value)}
              </select>
            </label>
          </.form>
          <button
            id="play-level"
            type="button"
            phx-click="play_level"
            phx-value-level={@level.level}
            phx-disable-with={dgettext("memory", "Starting...")}
            class="flex cursor-pointer items-center gap-1.5 rounded-full bg-octo-indigo px-6 py-2.5 font-medium text-white shadow-lg shadow-octo-indigo/25 transition hover:-translate-y-0.5 hover:bg-octo-indigo/90 hover:shadow-xl active:translate-y-0"
          >
            <%= cond do %>
              <% @level.status == :done -> %>
                {dgettext("memory", "Play again")}
              <% @level.cleared > 0 -> %>
                {dgettext("memory", "Try again")}
              <% true -> %>
                {dgettext("memory", "Play")}
            <% end %>
            <.icon name="hero-play-mini" class="size-4" />
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  # The grid of the level card: a full grid that is wider than tall, as
  # square as possible
  defp preview_layout(cards) do
    cards
    |> Board.layouts()
    |> Enum.filter(fn {columns, rows, _gaps} -> columns >= rows end)
    |> Enum.min_by(fn {columns, rows, gaps} -> {gaps, columns - rows} end)
  end

  # The possible size before (-1) or after (1) the current one, or nil
  defp step_size(sizes, cards, -1), do: sizes |> Enum.filter(&(&1 < cards)) |> List.last()
  defp step_size(sizes, cards, 1), do: Enum.find(sizes, &(&1 > cards))
end
