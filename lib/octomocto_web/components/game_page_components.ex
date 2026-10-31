defmodule OctomoctoWeb.GamePageComponents do
  @moduledoc """
  The parts of the settings page of each game: the list of public games
  (see `Octomocto.Lobby`), the Start game button, and the
  rules in a pop-up. All games have the same accent color, the brand
  indigo.
  """
  use Phoenix.Component
  use Gettext, backend: OctomoctoWeb.Gettext

  import OctomoctoWeb.CoreComponents, only: [icon: 1, show: 2, hide: 1]

  alias Phoenix.LiveView.JS

  attr :games, :list, required: true, doc: "see `Octomocto.Lobby.games/1`"

  attr :matches, :any,
    default: &__MODULE__.no_match/1,
    doc: "a function that is true for a game with the settings of the new game"

  attr :path, :any, required: true, doc: "a function that gives the path of a game"

  attr :new_game_path, :string,
    default: nil,
    doc: "the path of the settings of a new game, when they are on another tab"

  attr :watchers, :map,
    default: %{},
    doc: "the number of watchers of each game by its id, see `Octomocto.Lobby.watchers/1`"

  slot :icon, required: true, doc: "the image of a game, with the game as the argument"

  slot :summary,
    doc:
      "the settings of a game, with the game as the argument. Leave it out for a game with no settings to show: then the row has only the players."

  slot :action, doc: "an optional button at the right of the title"

  @doc """
  The public games: the open games that wait for players, then the games
  that have started. An open game with the same settings as the new game
  has a green background. In a started game, the player of the turn is in
  bold, and the points show when the game has them. The Watch button of a
  game with watchers shows their number.
  """
  def lobby_games(assigns) do
    ~H"""
    <section
      id="lobby-games"
      class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10"
    >
      <div class="mb-3 flex items-center justify-between gap-2">
        <h3 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-user-group" class={["size-4", "text-octo-indigo"]} /> {gettext(
            "Ongoing games"
          )}
        </h3>
        {render_slot(@action)}
      </div>
      <p
        :if={@games == []}
        id="lobby-games-empty"
        class="py-2 text-center text-sm text-base-content/50"
      >
        {gettext("No games now.")}
        <%= if @new_game_path do %>
          <.link
            id="lobby-games-new"
            patch={@new_game_path}
            class="font-medium text-octo-indigo transition hover:text-octo-indigo/80 hover:underline dark:text-octo-indigo-light"
          >
            {gettext("Make a public one.")}
          </.link>
        <% else %>
          {gettext("Make a public one.")}
        <% end %>
      </p>
      <ul :if={@games != []} id="lobby-games-list" class="-mx-2 space-y-1">
        <li
          :for={game <- @games}
          id={"lobby-game-#{game.id}"}
          class={[
            "flex items-center gap-3 rounded-xl px-2 py-2 transition-colors",
            if(game.status == :open and @matches.(game),
              do: "bg-emerald-50 dark:bg-emerald-500/10",
              else: "hover:bg-base-200/60"
            )
          ]}
        >
          {render_slot(@icon, game)}
          <div class="min-w-0 flex-1">
            <p :if={@summary != []} class="flex items-center gap-2 text-sm font-medium">
              <span class="line-clamp-2">{render_slot(@summary, game)}</span>
            </p>
            <p class={[
              "flex flex-wrap gap-x-2.5 text-base-content/70",
              if(@summary == [], do: "text-sm", else: "text-xs")
            ]}>
              <span :for={player <- game.players} class="flex items-center gap-1">
                <.presence away={player.away} />
                <span class={[
                  player[:turn] && !game[:finished] && "font-semibold text-base-content"
                ]}>
                  {player_name(player)}
                </span>
                <span :if={player[:score]} class="tabular-nums text-base-content/50">
                  {player.score}
                </span>
              </span>
            </p>
          </div>
          <%= if game.status == :open do %>
            <span class="shrink-0 text-xs tabular-nums text-base-content/50">
              {gettext("%{joined} of %{needed}",
                joined: game.players_needed - game.seats_left,
                needed: game.players_needed
              )}
            </span>
            <.link
              id={"join-#{game.id}"}
              href={@path.(game)}
              class={[
                "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium text-white shadow-sm transition hover:-translate-y-0.5 active:translate-y-0",
                "bg-octo-indigo hover:bg-octo-indigo/90"
              ]}
            >
              {gettext("Join")}
            </.link>
          <% else %>
            <span
              :if={game[:finished]}
              id={"finished-#{game.id}"}
              class="shrink-0 rounded-full bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-700 dark:text-amber-400"
            >
              {gettext("Finished")}
            </span>
            <.link
              :if={!game[:finished]}
              id={"watch-#{game.id}"}
              href={@path.(game) <> "?watch=1"}
              class={[
                "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium ring-1 transition hover:-translate-y-0.5 active:translate-y-0",
                "text-octo-indigo ring-octo-indigo/30 hover:bg-octo-mist dark:text-octo-indigo-light dark:hover:bg-octo-indigo-light/10"
              ]}
            >
              {gettext("Watch")}
              <span
                :if={@watchers[game.id]}
                id={"watchers-#{game.id}"}
                class="tabular-nums opacity-70"
              >
                · {@watchers[game.id]}
              </span>
            </.link>
          <% end %>
        </li>
      </ul>
    </section>
    """
  end

  @doc false
  def no_match(_game), do: false

  attr :players, :list,
    required: true,
    doc: "the players of the match, each with `:id`, `:name`, `:color`, `:color_name` and `:wins`"

  attr :ties, :integer, required: true
  attr :me, :string, default: nil, doc: "the id of the player on the page"
  attr :back, :string, required: true, doc: "the path of the game"

  @doc """
  The score of a match on the settings page, in place of the Players
  setting: the wins of each player, the most wins first, and the ties. The
  player on the page changes the settings of the next field, and the
  other players wait.
  """
  def match_score(assigns) do
    assigns = assign(assigns, :players, Enum.sort_by(assigns.players, & &1.wins, :desc))

    ~H"""
    <section
      id="match-score"
      class="rounded-2xl bg-base-100 p-5 text-start shadow-sm ring-1 ring-base-content/10"
    >
      <div class="flex items-center justify-between gap-2">
        <h3 class="flex items-center gap-2 font-semibold">
          <.icon name="hero-trophy" class="size-4 text-octo-indigo" /> {gettext("Match")}
        </h3>
        <a
          id="match-back"
          href={@back}
          class="group flex items-center gap-1 text-sm font-medium text-octo-indigo transition hover:text-octo-indigo/80 dark:text-octo-indigo-light"
        >
          <.icon
            name="hero-arrow-uturn-left"
            class="size-3.5 transition group-hover:-translate-x-0.5 rtl:-scale-x-100 rtl:group-hover:translate-x-0.5"
          />
          {gettext("Back to the game")}
        </a>
      </div>
      <div class="mt-3 flex justify-end text-xs font-medium tracking-wide text-base-content/50 uppercase">
        {gettext("Wins")}
      </div>
      <ul id="match-players" class="divide-y divide-base-content/5">
        <li
          :for={player <- @players}
          id={"match-player-#{player.id}"}
          class="flex items-center gap-3 py-2"
        >
          <span class="size-3 shrink-0 rounded-full" style={"background: #{player.color}"} />
          <span class="min-w-0 flex-1 truncate">
            {player_name(player)}
            <span :if={player.id == @me} class="text-base-content/50">({gettext("you")})</span>
          </span>
          <span class="text-xl font-semibold tabular-nums">{player.wins}</span>
        </li>
      </ul>
      <p :if={@ties > 0} id="match-ties" class="mt-1 text-end text-sm text-base-content/60">
        {ngettext("%{count} tie", "%{count} ties", @ties)}
      </p>
      <p class="mt-2 text-xs text-base-content/50">
        {gettext("The other players wait until you start the next game.")}
      </p>
    </section>
    """
  end

  attr :multiplayer, :boolean, required: true, doc: "shows the hint about the link"
  attr :match, :boolean, default: false, doc: "starts the next game of a match"

  @doc """
  The Start game button, or the Create game button for a multiplayer
  game, because other players must join before it starts. It sends
  `"new_game"`. It stays at the bottom of
  the screen while the settings above it do not fit, so that a new player
  sees how to start. The settings go under it into the page color. It is
  wider than the settings, so that it also covers the borders of the
  cards, which are outside of the cards. Only the button takes clicks, so
  that the settings under the fade stay clickable.
  """
  def start_bar(assigns) do
    ~H"""
    <div
      id="new-game-bar"
      class="pointer-events-none sticky bottom-0 z-10 -mx-2 -mt-6 flex w-[calc(100%+1rem)] flex-col items-center gap-2 bg-linear-to-t from-base-100 from-70% to-transparent pt-8 pb-5"
    >
      <button
        id="new-game"
        type="button"
        phx-click="new_game"
        phx-disable-with={
          if(@multiplayer and not @match, do: gettext("Creating..."), else: gettext("Starting..."))
        }
        class={[
          "pointer-events-auto cursor-pointer rounded-full px-8 py-3 font-medium text-white shadow-lg transition hover:-translate-y-0.5 hover:shadow-xl active:translate-y-0",
          "bg-octo-indigo shadow-octo-indigo/25 hover:bg-octo-indigo/90"
        ]}
      >
        <%= cond do %>
          <% @match -> %>
            {gettext("Start next game")}
          <% @multiplayer -> %>
            {gettext("Create game")}
          <% true -> %>
            {gettext("Start game")}
        <% end %>
      </button>
      <p :if={@multiplayer and not @match} class="text-sm text-base-content/50">
        {gettext("You get a link to share with other players.")}
      </p>
    </div>
    """
  end

  @doc "The link that opens the `rules/1` pop-up."
  def how_to_play(assigns) do
    ~H"""
    <button
      id="how-to-play"
      type="button"
      phx-click={show_rules()}
      class={[
        "inline-flex cursor-pointer items-center gap-1 text-sm font-medium transition",
        "text-octo-indigo hover:text-octo-indigo/80"
      ]}
    >
      <.icon name="hero-question-mark-circle" class="size-4" /> {gettext("How to play")}
    </button>
    """
  end

  attr :rules, :list, required: true, doc: "the rules, one sentence or more each"

  @doc """
  The rules of the game in a pop-up. It opens and closes in the browser,
  with no call to the server.
  """
  def rules(assigns) do
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
            <h2 id="rules-title" class="text-xl font-semibold">{gettext("How to play")}</h2>
            <button
              id="rules-close"
              type="button"
              phx-click={hide_rules()}
              aria-label={gettext("Close")}
              class="grid size-9 cursor-pointer place-items-center rounded-full text-base-content/60 transition hover:bg-base-200 hover:text-base-content"
            >
              <.icon name="hero-x-mark" class="size-5" />
            </button>
          </div>
          <ul class="space-y-2.5 text-base-content/80">
            <li :for={rule <- @rules} class="flex gap-3">
              <span class={["mt-2.5 size-1.5 shrink-0 rounded-full", "bg-octo-indigo"]} />
              <span>{rule}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  attr :away, :boolean, required: true

  # Green while the player is online, grey during the grace time
  @doc """
  The hint under the Visibility setting. A game for one player has no free
  seats, so others can only watch it.
  """
  def visibility_hint(%{players: 1, public: true}),
    do: gettext("Other players can watch this game in Ongoing games.")

  def visibility_hint(%{players: 1, public: false}),
    do: gettext("Only players with the link can watch.")

  def visibility_hint(%{public: true}),
    do: gettext("Other players see this game in Ongoing games.")

  def visibility_hint(%{public: false}), do: gettext("Only players with the link can join.")

  defp presence(assigns) do
    ~H"""
    <span class={[
      "size-1.5 rounded-full transition-colors",
      if(@away, do: "bg-base-content/25", else: "bg-emerald-500")
    ]} />
    """
  end

  @doc "The names of the colors of the players, the same in all games."
  def color_names do
    [
      gettext_noop("pink"),
      gettext_noop("sky"),
      gettext_noop("lime"),
      gettext_noop("amber"),
      gettext_noop("violet"),
      gettext_noop("red"),
      gettext_noop("teal"),
      gettext_noop("indigo")
    ]
  end

  @doc "The name of a color of a player in the language of the page."
  def color_name(name), do: Gettext.gettext(OctomoctoWeb.Gettext, name)

  # A guest has the name of its color
  defp player_name(%{name: nil, color_name: name}),
    do: name |> color_name() |> String.capitalize()

  defp player_name(%{name: name}), do: name

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
end
