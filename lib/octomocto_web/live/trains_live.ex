defmodule OctomoctoWeb.TrainsLive do
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, "trains"}
  on_mount OctomoctoWeb.BestResults

  # The same settings and result lists as on the Nimble Mosaic page
  import OctomoctoWeb.SettingsComponents,
    only: [
      preview_rows: 1,
      sparkline: 1,
      setting: 1,
      setting_header: 1,
      option: 1,
      score_list: 1,
      player_list: 1,
      result_row: 1,
      result_pill: 1,
      player_name: 1
    ]

  import OctomoctoWeb.GamePageComponents
  import OctomoctoWeb.CampaignComponents

  alias Octomocto.{Lobby, Trains}
  alias Octomocto.Trains.{Campaign, Game, Store}
  alias OctomoctoWeb.{SavedSettings, TrainsChannel}

  def mount(params, _session, socket) do
    match = match(params["match"], socket)
    if connected?(socket) and !match, do: Lobby.subscribe(Game)

    if match && connected?(socket),
      do: Phoenix.PubSub.subscribe(Octomocto.PubSub, Game.topic(match.id))

    {:ok,
     socket
     |> assign([rules: rules(), match: match] ++ seo())
     |> assign_lobby(Lobby.entries(Game, Store))
     |> assign(watchers: Lobby.watchers(Game))}
  end

  @doc "The title and the description of the Right on Track pages, for search engines."
  def seo do
    [
      page_title: dgettext("trains", "Right on Track: a Train of Thought-Like Game"),
      page_description:
        dgettext(
          "trains",
          "Click the switches to send each train to the house with its colors. Similar to Train of Thought on Lumosity. Free, in your browser."
        )
    ]
  end

  # The params of the Free play tab. Without them, the page opens
  # the tab that the user or the guest used last.
  @settings_params ["players", "switches", "trains", "pace", "visibility", "match"]

  def handle_params(params, uri, %{assigns: %{live_action: :campaign}} = socket) do
    {:noreply,
     socket
     |> remember_tab("campaign")
     |> assign_seo_links(uri)
     |> assign(
       settings: settings(tab_params(socket)),
       languages: Locale.languages("trains", socket.assigns.locale, ~p"/trains/campaign")
     )
     |> assign_campaign(params)}
  end

  # The public games, and the results of the settings of the Free play tab
  def handle_params(_params, uri, %{assigns: %{live_action: :lobby}} = socket) do
    {:noreply,
     socket
     |> remember_tab("lobby")
     |> assign_free_play(tab_params(socket))
     |> assign_seo_links(uri)
     |> assign(languages: Locale.languages("trains", socket.assigns.locale, ~p"/trains/lobby"))}
  end

  def handle_params(params, uri, socket) do
    tab = SavedSettings.last_tab(socket, "trains")

    if tab in ["campaign", "lobby"] and not Enum.any?(@settings_params, &Map.has_key?(params, &1)) do
      {:noreply, push_patch(socket, to: Locale.path(socket.assigns.locale, ~p"/trains/#{tab}"))}
    else
      new_socket =
        socket
        |> remember_tab("free")
        |> assign_free_play(saved_params(socket, params))
        |> assign_seo_links(uri)

      settings = new_socket.assigns.settings

      SavedSettings.save_change(
        socket,
        "trains",
        settings,
        settings_query(%{settings | match: nil})
      )

      {:noreply, new_socket}
    end
  end

  # The tabs and the settings are one page for search engines: the game
  # page. Only the game page itself has the hreflang links.
  defp assign_seo_links(socket, uri) do
    canonical_url =
      OctomoctoWeb.Endpoint.url() <> Locale.path(socket.assigns.locale, ~p"/trains")

    assign(socket,
      canonical_url: canonical_url,
      alternate_urls: Locale.alternate_urls(uri, canonical_url, "trains", ~p"/trains")
    )
  end

  # The settings that the user chose last, when the page
  # loads without settings. A match has its own settings.
  defp saved_params(%{assigns: %{match: nil}} = socket, params),
    do: SavedSettings.params(socket, "trains", params, @settings_params)

  defp saved_params(_socket, params), do: params

  # The Campaign and Lobby tabs keep the settings of the Free play tab, so
  # that its tab link goes back to them
  defp tab_params(%{assigns: %{settings: settings}}),
    do: SavedSettings.to_params(settings_query(%{settings | match: nil}))

  defp tab_params(socket), do: saved_params(socket, %{})

  defp remember_tab(socket, tab), do: SavedSettings.remember_tab(socket, "trains", tab)

  defp assign_free_play(socket, params) do
    match = socket.assigns.match
    settings = params |> match_params(match) |> settings() |> match_settings(match)

    filter = %{
      "switch_count" => settings.switch_count,
      "trains_per_house" => settings.trains_per_house,
      "pace" => settings.pace,
      "players" => settings.players
    }

    assign(socket,
      settings: settings,
      # The other language keeps the settings
      languages:
        Locale.languages(
          "trains",
          socket.assigns.locale,
          ~p"/trains?#{settings_query(settings)}"
        ),
      switch_counts: Trains.switch_counts(settings.players),
      user_results: user_results(socket.assigns.current_scope, filter)
    )
    |> OctomoctoWeb.BestResults.assign_best(Trains, filter)
    |> OctomoctoWeb.ResultsPreview.assign_preview(:score, max: trains(settings))
  end

  # The levels of the campaign with the progress of the user, and the
  # selected level (`?level=`, else the next level to play). A guest sees
  # the levels of a new player.
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

        correct = if run, do: run.best_correct, else: 0

        Map.merge(level, %{
          status: status,
          correct: correct,
          percent: div(100 * correct, level.trains)
        })
      end)

    selected =
      case Integer.parse(params["level"] || "") do
        {n, ""} when n in 1..length(levels)//1 -> n
        _ -> min(highest + 1, length(levels))
      end

    assign(socket,
      campaign: %{
        levels: levels,
        selected: Enum.at(levels, selected - 1),
        highest: highest,
        leaderboard: Campaign.leaderboard()
      }
    )
  end

  def handle_info({:lobby_changed, _game, id, entry}, socket) do
    {:noreply, assign_lobby(socket, Lobby.put_entry(socket.assigns.lobby, id, entry))}
  end

  # A watcher came or left, see `Octomocto.Lobby.watch/3`
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, watchers: Lobby.watchers(Game))}
  end

  # The match card shows the changes of the players
  def handle_info({:trains_state, state}, socket) do
    {:noreply, update(socket, :match, &%{&1 | state: state})}
  end

  def handle_info({:trains_flip, _flip}, socket), do: {:noreply, socket}
  def handle_info({:trains_decision, _decision}, socket), do: {:noreply, socket}

  # The pill text of a row in the list of the highest levels
  defp highest_level_text(level) do
    if level == Campaign.count(),
      do: dngettext("trains", "All %{count} level", "All %{count} levels", level),
      else: dgettext("trains", "Level %{level}", level: level)
  end

  @doc """
  Starts a game in the default settings for the number of players, and
  gives its id. See `OctomoctoWeb.NextGame`.
  """
  def create_default_game(players, public) do
    # Any player can start the next game, thus it has no creator (see
    # `Octomocto.Seats`)
    %{settings(%{"players" => Integer.to_string(players)}) | public: public}
    |> Map.put(:creator, false)
    |> Trains.create_game()
  end

  def handle_event(
        "play_level",
        %{"level" => level},
        %{assigns: %{current_scope: %{user: user}}} = socket
      ) do
    with {n, ""} <- Integer.parse(level),
         {:ok, id} <- Campaign.start(user.id, n) do
      {:noreply, redirect(socket, to: Locale.path(socket.assigns.locale, ~p"/trains/#{id}"))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("play_level", _params, socket), do: {:noreply, socket}

  # The next round of the match, in the same game
  def handle_event("new_game", _params, %{assigns: %{match: %{player_id: player_id}}} = socket)
      when is_binary(player_id) do
    %{match: match, settings: settings, locale: locale} = socket.assigns
    # When the settings do not change (for example, the game stopped), the
    # game page shows the end screen again
    Trains.change_settings(
      match.id,
      player_id,
      Map.take(settings, [:switch_count, :trains_per_house, :pace])
    )

    {:noreply, redirect(socket, to: Locale.path(locale, ~p"/trains/#{match.id}"))}
  end

  def handle_event("new_game", _params, socket) do
    id = Trains.create_game(socket.assigns.settings)
    {:noreply, redirect(socket, to: Locale.path(socket.assigns.locale, ~p"/trains/#{id}"))}
  end

  # One player, 6 switches, 2 trains for each house, the normal pace and a
  # public game, when the params do not say otherwise. The switches must
  # divide equally between the players.
  defp settings(params) do
    players = int_param(params["players"], 1..4, 1)
    switches = int_param(params["switches"], 1..12, 6)

    %{
      players: players,
      switch_count: Trains.fit_switch_count(switches, players),
      trains_per_house: int_param(params["trains"], 1..7, 2),
      pace: if(params["pace"] in Trains.paces(), do: params["pace"], else: "normal"),
      public: params["visibility"] != "private",
      match: nil
    }
  end

  # The match of the page (`?match=<game id>`, see `Octomocto.Trains.Game`),
  # or nil: the `:id` of the game, the `:state` that its clients see, and
  # the `:player_id` of the player who changes the settings. The token of
  # the player is in the connect params (see app.js), so the page holds the
  # seat of the player only after the connect. Before the connect, the page
  # only shows the players.
  defp match(id, socket) when is_binary(id) do
    if connected?(socket) do
      token = get_connect_params(socket)["match_token"]

      with player_id when is_binary(player_id) <- TrainsChannel.player_id(id, token),
           {:ok, state} <- Trains.edit_settings(id, player_id) do
        %{id: id, player_id: player_id, state: state}
      else
        _ -> nil
      end
    else
      case Store.read(id) do
        %{needed: needed, campaign: nil} = state when needed > 1 ->
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
        "switches" => Integer.to_string(state.switch_count),
        "trains" => Integer.to_string(state.trains_per_house),
        "pace" => state.pace
      },
      # A match keeps its players, and the switches must divide equally
      # between them
      Map.put(params, "players", Integer.to_string(state.players_needed))
    )
  end

  # A match keeps its players and its visibility
  defp match_settings(settings, nil), do: settings

  defp match_settings(settings, %{id: id, state: state}),
    do: %{settings | public: state.public, match: id}

  defp assign_lobby(socket, entries) do
    assign(socket, lobby: entries, lobby_games: Lobby.games(entries))
  end

  # Nil for a guest
  defp user_results(%{user: _} = scope, filter), do: Trains.user_results(scope, filter)
  defp user_results(nil, _filter), do: nil

  defp rules do
    [
      dgettext(
        "trains",
        "Trains leave the station one at a time. Each train has the colors of one of the houses."
      ),
      dgettext(
        "trains",
        "The tracks split at the switches. Click a switch to change its direction. A train follows the direction of each switch on its way."
      ),
      dgettext("trains", "Send each train to the house with its colors."),
      dgettext(
        "trains",
        "With more players, each player owns some of the switches and can change only those."
      ),
      dgettext("trains", "The pace tells how fast the trains come one after another."),
      dgettext(
        "trains",
        "The round ends when all trains have arrived. The score is the number of trains that got to the correct house."
      ),
      dgettext(
        "trains",
        "Right on Track is a Train of Thought-like game. Lumosity and Train of Thought are trademarks of Lumos Labs. Octomocto is not affiliated with Lumos Labs."
      )
    ]
  end

  defp int_param(value, range, default) do
    case Integer.parse(value || "") do
      {n, ""} -> if n in range, do: n, else: default
      _ -> default
    end
  end

  @doc """
  The path of this page in the language with the settings of the game in
  the given state. For a game of the campaign, the map with its level.
  """
  def settings_path(locale, %{campaign: %{level: level}}), do: campaign_path(locale, level)

  def settings_path(locale, state) do
    settings = %{
      players: state.needed,
      switch_count: state.switch_count,
      trains_per_house: state.trains_per_house,
      pace: state.pace,
      public: state.public,
      match: nil
    }

    settings_path(locale, settings, %{})
  end

  @doc """
  The path of the Change settings button of the game in the language, or
  nil for a game with one player or of the campaign. The page changes
  the settings of the next round of the match (see
  `Octomocto.Trains.Game`). The path has only the match, because the
  settings of the game can change after the page load.
  """
  def match_path(locale, %{needed: needed, campaign: nil} = state) when needed > 1,
    do: Locale.path(locale, ~p"/trains?#{[match: state.id]}")

  def match_path(_locale, _state), do: nil

  @doc "The path of the Campaign tab in the language with the level selected."
  def campaign_path(locale, level),
    do: Locale.path(locale, ~p"/trains/campaign?#{[level: level]}")

  # The start page in the language with the settings, and with the given changes
  defp settings_path(locale, settings, changes) do
    Locale.path(locale, ~p"/trains?#{settings_query(Map.merge(settings, changes))}")
  end

  # The query of the start page for the settings
  defp settings_query(s) do
    query = [
      players: s.players,
      switches: s.switch_count,
      trains: s.trains_per_house,
      pace: s.pace
    ]

    # A public game has no param, so that most links stay short
    query = if s.public, do: query, else: query ++ [visibility: "private"]
    if s.match, do: query ++ [match: s.match], else: query
  end

  @doc """
  The settings of a game in the list of public games, and the score when
  the round ended. In a campaign game, the word "Campaign" is a link to the
  campaign page.
  """
  def game_summary(%{id: id, settings: settings} = game) do
    summary =
      Enum.join(
        [
          switches(settings.switch_count),
          dgettext("trains", "%{count} per house", count: settings.trains_per_house),
          pace_name(settings.pace)
        ],
        " · "
      )

    summary =
      if game[:score],
        do: summary <> " · " <> format_score(game.score, game.trains),
        else: summary

    case settings do
      %{campaign: level} ->
        assigns = %{
          id: id,
          level: dgettext("trains", "Level %{level}", level: level),
          summary: summary,
          path: Locale.path(Gettext.get_locale(OctomoctoWeb.Gettext), ~p"/trains/campaign")
        }

        ~H"""
        <.link
          id={"lobby-campaign-#{@id}"}
          navigate={@path}
          class="text-octo-indigo transition hover:underline dark:text-octo-indigo-light"
        >{dgettext("trains", "Campaign")}</.link>
        · {@level} · {@summary}
        """

      _ ->
        summary
    end
  end

  # The number of trains of a round with the settings
  defp trains(settings), do: settings.trains_per_house * (settings.switch_count + 1)

  # The part of the trains that got home, for example "92%"
  defp format_score(score, trains), do: "#{round(score * 100 / trains)}%"

  defp switches(count), do: dngettext("trains", "%{count} switch", "%{count} switches", count)

  defp pace_name("easy"), do: dgettext("trains", "Easy")
  defp pace_name("normal"), do: dgettext("trains", "Normal")
  defp pace_name("hard"), do: dgettext("trains", "Hard")
  defp pace_name("expert"), do: dgettext("trains", "Expert")

  # Tells what a number of switches gives: there is one more house than switches
  defp switches_hint(switches, 1),
    do: dngettext("trains", "%{count} house.", "%{count} houses.", switches + 1)

  defp switches_hint(switches, players) do
    switches_hint(switches, 1) <>
      " " <>
      dngettext(
        "trains",
        "Each player owns %{count} switch.",
        "Each player owns %{count} switches.",
        div(switches, players)
      )
  end

  defp trains_hint(%{switch_count: switches, trains_per_house: n}),
    do: dngettext("trains", "%{count} train.", "%{count} trains.", n * (switches + 1))

  defp pace_hint("easy"),
    do:
      dgettext(
        "trains",
        "The trains come a bit faster and faster: from 8 down to 6 seconds apart."
      )

  defp pace_hint("normal"),
    do: dgettext("trains", "The trains come faster and faster: from 6 down to 4 seconds apart.")

  defp pace_hint("hard"),
    do:
      dgettext(
        "trains",
        "From 5 down to 3 seconds apart. The trains get fast early in the game."
      )

  defp pace_hint("expert"),
    do:
      dgettext(
        "trains",
        "From 4 down to 2 seconds apart. The trains get very fast very early in the game."
      )

  attr :level, :map, required: true

  # The selected level: its settings, the trains that must get home and the
  # Play button (not for a locked level). It stays at the bottom of the
  # screen while the map does not fit, so that the Play button is always in
  # view.
  defp level_card(assigns) do
    assigns = assign(assigns, pass: Campaign.pass_count(assigns.level.trains))

    ~H"""
    <div
      id="level-card"
      class="sticky bottom-3 z-10 flex w-full flex-wrap items-center gap-x-5 gap-y-4 rounded-2xl bg-white p-5 text-start shadow-lg ring-1 ring-base-content/10 dark:bg-base-100"
    >
      <div class={[
        "grid size-12 shrink-0 place-items-center rounded-2xl",
        if(@level.status == :locked,
          do: "bg-base-200 grayscale opacity-50",
          else: "bg-octo-indigo/10"
        )
      ]}>
        <OctomoctoWeb.GameIcons.game_icon game="trains" class="size-9" />
      </div>
      <div class="min-w-40 flex-1">
        <h3 id="level-card-title" class="flex items-center gap-1.5 font-semibold">
          {dgettext("trains", "Level %{level}", level: @level.level)}
          <.icon
            :if={@level.status == :done}
            name="hero-check-circle-mini"
            class="size-5 text-octo-indigo"
          />
        </h3>
        <p class="text-sm text-base-content/60">
          {switches(@level.switch_count)} · {dngettext(
            "trains",
            "%{count} train",
            "%{count} trains",
            @level.trains
          )} · {pace_name(@level.pace)}
        </p>
        <p class="text-sm text-base-content/60">
          <%= if @level.status != :locked and @level.correct > 0 do %>
            {dgettext("trains", "Best: %{correct} of %{trains} home · %{pass} to pass",
              correct: @level.correct,
              trains: @level.trains,
              pass: @pass
            )}
          <% else %>
            {dgettext("trains", "Get %{pass} of %{trains} trains home to pass.",
              pass: @pass,
              trains: @level.trains
            )}
          <% end %>
        </p>
      </div>
      <button
        :if={@level.status != :locked}
        id="play-level"
        type="button"
        phx-click="play_level"
        phx-value-level={@level.level}
        phx-disable-with={dgettext("trains", "Starting...")}
        class="flex cursor-pointer items-center gap-1.5 rounded-full bg-octo-indigo px-6 py-2.5 font-medium text-white shadow-lg shadow-octo-indigo/25 transition hover:bg-octo-indigo/90 hover:shadow-xl"
      >
        <%= cond do %>
          <% @level.status == :done -> %>
            {dgettext("trains", "Play again")}
          <% @level.correct > 0 -> %>
            {dgettext("trains", "Try again")}
          <% true -> %>
            {dgettext("trains", "Play")}
        <% end %>
        <.icon name="hero-play-mini" class="size-4" />
      </button>
    </div>
    """
  end
end
