defmodule OctomoctoWeb.GamePageComponents do
  @moduledoc """
  The parts of the settings page of each game: the lists of open and
  ongoing games (see `Octomocto.Lobby`), the Start game button, and the
  rules in a pop-up. Each game has its own `accent` color: `:sky`,
  `:emerald` or `:violet`.
  """
  use Phoenix.Component

  import OctomoctoWeb.CoreComponents, only: [icon: 1, show: 2, hide: 1]

  alias Phoenix.LiveView.JS

  attr :games, :list, required: true, doc: "see `Octomocto.Lobby.open_games/1`"

  attr :matches, :any,
    required: true,
    doc: "a function that is true for a game with the settings of the new game"

  attr :path, :any, required: true, doc: "a function that gives the path of a game by its id"
  attr :accent, :atom, required: true
  slot :icon, required: true, doc: "the image of a game, with the game as the argument"
  slot :summary, required: true, doc: "the settings of a game, with the game as the argument"

  @doc """
  The public games that wait for players. A game with the same settings as
  the new game has a green background.
  """
  def open_games(assigns) do
    ~H"""
    <section
      id="open-games"
      class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10"
    >
      <h3 class="mb-3 flex items-center gap-2 font-semibold">
        <.icon name="hero-user-group" class={["size-4", accent(@accent, :icon)]} /> Open games
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
            if(@matches.(game),
              do: "bg-emerald-50 dark:bg-emerald-500/10",
              else: "hover:bg-base-200/60"
            )
          ]}
        >
          {render_slot(@icon, game)}
          <div class="min-w-0 flex-1">
            <p class="truncate text-sm font-medium">{render_slot(@summary, game)}</p>
            <p class="flex flex-wrap gap-x-2.5 text-xs text-base-content/70">
              <span :for={player <- game.players} class="flex items-center gap-1">
                <.presence away={player.away} />
                {player_name(player)}
              </span>
            </p>
          </div>
          <span class="shrink-0 text-xs tabular-nums text-base-content/50">
            {game.players_needed - game.seats_left} of {game.players_needed}
          </span>
          <.link
            id={"join-#{game.id}"}
            href={@path.(game.id)}
            class={[
              "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium text-white shadow-sm transition hover:-translate-y-0.5 active:translate-y-0",
              accent(@accent, :button)
            ]}
          >
            Join
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  attr :games, :list, required: true, doc: "see `Octomocto.Lobby.ongoing_games/1`"
  attr :path, :any, required: true, doc: "a function that gives the path of a game by its id"
  attr :accent, :atom, required: true
  slot :icon, required: true, doc: "the image of a game, with the game as the argument"
  slot :summary, required: true, doc: "the settings of a game, with the game as the argument"

  @doc """
  The public games that have started. The player of the turn is in bold,
  and the points show when the game has them.
  """
  def ongoing_games(assigns) do
    ~H"""
    <section
      id="ongoing-games"
      class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10"
    >
      <h3 class="mb-3 flex items-center gap-2 font-semibold">
        <.icon name="hero-play-circle" class={["size-4", accent(@accent, :icon)]} /> Ongoing games
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
          {render_slot(@icon, game)}
          <div class="min-w-0 flex-1">
            <p class="flex items-center gap-2 text-sm font-medium">
              <span class="truncate">{render_slot(@summary, game)}</span>
              <span
                :if={game.finished}
                class="shrink-0 rounded-full bg-amber-500/10 px-2 py-0.5 text-xs font-medium text-amber-700 dark:text-amber-400"
              >
                Finished
              </span>
            </p>
            <p class="flex flex-wrap gap-x-2.5 text-xs text-base-content/70">
              <span :for={player <- game.players} class="flex items-center gap-1">
                <.presence away={player.away} />
                <span class={[
                  player[:turn] && not game.finished && "font-semibold text-base-content"
                ]}>
                  {player_name(player)}
                </span>
                <span :if={player[:score]} class="tabular-nums text-base-content/50">
                  {player.score}
                </span>
              </span>
            </p>
          </div>
          <.link
            id={"watch-#{game.id}"}
            href={@path.(game.id) <> "?watch=1"}
            class={[
              "shrink-0 rounded-full px-4 py-1.5 text-sm font-medium ring-1 transition hover:-translate-y-0.5 active:translate-y-0",
              accent(@accent, :outline)
            ]}
          >
            Watch
          </.link>
        </li>
      </ul>
    </section>
    """
  end

  attr :accent, :atom, required: true
  attr :multiplayer, :boolean, required: true, doc: "shows the hint about the link"

  @doc """
  The Start game button. It sends `"new_game"`. It stays at the bottom of
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
        phx-disable-with="Starting..."
        class={[
          "pointer-events-auto cursor-pointer rounded-full px-8 py-3 font-medium text-white shadow-lg transition hover:-translate-y-0.5 hover:shadow-xl active:translate-y-0",
          accent(@accent, :start)
        ]}
      >
        Start game
      </button>
      <p :if={@multiplayer} class="text-sm text-base-content/50">
        You get a link to share with other players.
      </p>
    </div>
    """
  end

  attr :accent, :atom, required: true

  @doc "The link that opens the `rules/1` pop-up."
  def how_to_play(assigns) do
    ~H"""
    <button
      id="how-to-play"
      type="button"
      phx-click={show_rules()}
      class={[
        "inline-flex cursor-pointer items-center gap-1 text-sm font-medium transition",
        accent(@accent, :link)
      ]}
    >
      <.icon name="hero-question-mark-circle" class="size-4" /> How to play
    </button>
    """
  end

  attr :rules, :list, required: true, doc: "the rules, one sentence or more each"
  attr :accent, :atom, required: true

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
            <li :for={rule <- @rules} class="flex gap-3">
              <span class={["mt-2.5 size-1.5 shrink-0 rounded-full", accent(@accent, :bullet)]} />
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
    do: "Other players can watch this game in Ongoing games."

  def visibility_hint(%{players: 1, public: false}), do: "Only players with the link can watch."
  def visibility_hint(%{public: true}), do: "Other players see this game in Open games."
  def visibility_hint(%{public: false}), do: "Only players with the link can join."

  defp presence(assigns) do
    ~H"""
    <span class={[
      "size-1.5 rounded-full transition-colors",
      if(@away, do: "bg-base-content/25", else: "bg-emerald-500")
    ]} />
    """
  end

  # A guest has the name of its color
  defp player_name(%{name: nil, color_name: color_name}), do: String.capitalize(color_name)
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

  # The full class names, so that Tailwind finds them
  defp accent(:sky, :icon), do: "text-sky-600"
  defp accent(:sky, :link), do: "text-sky-600 hover:text-sky-500"
  defp accent(:sky, :bullet), do: "bg-sky-500"
  defp accent(:sky, :button), do: "bg-sky-600 hover:bg-sky-500"
  defp accent(:sky, :start), do: "bg-sky-600 shadow-sky-600/25 hover:bg-sky-500"

  defp accent(:sky, :outline),
    do: "text-sky-700 ring-sky-600/30 hover:bg-sky-50 dark:text-sky-400 dark:hover:bg-sky-500/10"

  defp accent(:emerald, :icon), do: "text-emerald-600"
  defp accent(:emerald, :link), do: "text-emerald-600 hover:text-emerald-500"
  defp accent(:emerald, :bullet), do: "bg-emerald-500"
  defp accent(:emerald, :button), do: "bg-emerald-600 hover:bg-emerald-500"
  defp accent(:emerald, :start), do: "bg-emerald-600 shadow-emerald-600/25 hover:bg-emerald-500"

  defp accent(:emerald, :outline),
    do:
      "text-emerald-700 ring-emerald-600/30 hover:bg-emerald-50 dark:text-emerald-400 dark:hover:bg-emerald-500/10"

  defp accent(:violet, :icon), do: "text-violet-600"
  defp accent(:violet, :link), do: "text-violet-600 hover:text-violet-500"
  defp accent(:violet, :bullet), do: "bg-violet-500"
  defp accent(:violet, :button), do: "bg-violet-600 hover:bg-violet-500"
  defp accent(:violet, :start), do: "bg-violet-600 shadow-violet-600/25 hover:bg-violet-500"

  defp accent(:violet, :outline),
    do:
      "text-violet-700 ring-violet-600/30 hover:bg-violet-50 dark:text-violet-400 dark:hover:bg-violet-500/10"
end
