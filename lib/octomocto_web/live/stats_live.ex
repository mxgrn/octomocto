defmodule OctomoctoWeb.StatsLive do
  @moduledoc """
  The page with the number of games played in each of the last days. A
  LiveView, so that a click on a game in the legend of the chart adds or
  removes its line, and the chart fits the lines that stay.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, nil}

  alias Octomocto.Stats
  alias OctomoctoWeb.{GameIcons, HomeLive}

  @days 30

  # The size of the SVG coordinates of the chart. The SVG stretches to the
  # size of the plot, so only the proportions of the values are important.
  @width 1000
  @height 200

  # The number of horizontal lines above the zero line
  @ticks 4

  def mount(_params, _session, socket) do
    days = Stats.games_per_day(@days)

    {:ok,
     assign(socket,
       page_title: "Stats",
       noindex: true,
       days: days,
       total: days |> Enum.map(& &1.total) |> Enum.sum(),
       games: HomeLive.games(),
       by_game: games_by_count(days),
       by_language: Stats.games_by_language(@days),
       hidden: MapSet.new()
     )}
  end

  def handle_event("toggle_game", %{"id" => id}, socket) do
    hidden = socket.assigns.hidden

    hidden =
      if MapSet.member?(hidden, id), do: MapSet.delete(hidden, id), else: MapSet.put(hidden, id)

    {:noreply, assign(socket, hidden: hidden)}
  end

  # The games of the front page with their totals for all days, the most
  # played first
  defp games_by_count(days) do
    HomeLive.games()
    |> Enum.map(fn game ->
      Map.put(game, :count, days |> Enum.map(&games_in(&1, game)) |> Enum.sum())
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Renders a line chart with one line for each game, as in Google Analytics.
  A pointer on a day (or the keyboard focus) shows a vertical line, a dot on
  each game with games in the day, and the counts of all games in the day.
  Each game has a fixed color (see `--series-1` to `--series-9` in
  `app.css`), in the order of the games on the front page. A click on a
  game in the legend sends `toggle_game` with the id of the game. The
  hidden games have no line, and the y-axis fits the other games. A pointer
  on a shown game in the legend (or the keyboard focus) makes the lines of
  the other games pale (see `#games-chart` in `app.css`).
  """
  attr :days, :list, required: true, doc: "the days of `Octomocto.Stats.games_per_day/2`"
  attr :games, :list, required: true, doc: "the games of the front page, in their order"
  attr :hidden, :any, required: true, doc: "the ids of the games without a line, a MapSet"

  def games_chart(assigns) do
    visible = Enum.reject(assigns.games, &MapSet.member?(assigns.hidden, &1.id))
    step = days_step(assigns.days, visible)
    max = step * @ticks
    count = length(assigns.days)

    # The color of a game does not change when other games are hidden
    series =
      assigns.games
      |> Enum.with_index(1)
      |> Enum.reject(fn {game, _n} -> MapSet.member?(assigns.hidden, game.id) end)
      |> Enum.map(fn {game, n} ->
        points =
          assigns.days
          |> Enum.with_index()
          |> Enum.map(fn {day, i} ->
            {(i + 0.5) * @width / count, @height - games_in(day, game) / max * @height}
          end)

        %{game: game, n: n, color: "var(--series-#{n})", line: line_path(points)}
      end)

    assigns =
      assign(assigns,
        max: max,
        ticks: Enum.map(0..@ticks, &(&1 * step)),
        count: count,
        series: series,
        colors: Enum.with_index(assigns.games, 1),
        view_box: "0 0 #{@width} #{@height}"
      )

    ~H"""
    <div id="games-chart" class="select-none">
      <ul id="games-legend" class="mt-6 -ml-2 flex flex-wrap gap-1 text-xs">
        <li :for={{game, n} <- @colors}>
          <button
            id={"legend-#{game.id}"}
            type="button"
            phx-click="toggle_game"
            phx-value-id={game.id}
            data-legend={n}
            aria-pressed={to_string(not MapSet.member?(@hidden, game.id))}
            class={[
              "flex items-center gap-1.5 rounded-full px-2 py-1 transition",
              "text-base-content/70 hover:bg-base-200 hover:text-base-content active:scale-95",
              "aria-[pressed=false]:text-base-content/35 aria-[pressed=false]:line-through"
            ]}
          >
            <span
              class="h-0.5 w-3 rounded-full transition"
              style={
                if MapSet.member?(@hidden, game.id),
                  do: "background-color: currentColor",
                  else: "background-color: var(--series-#{n})"
              }
            ></span>
            {game.name}
          </button>
        </li>
      </ul>

      <div class="relative mt-6 ml-10 h-56 sm:h-64">
        <div
          :for={tick <- @ticks}
          class="absolute inset-x-0 border-t border-base-content/10"
          style={"bottom: #{percent(tick, @max)}%"}
        >
          <span class="absolute -left-10 w-8 -translate-y-1/2 text-right text-xs text-base-content/50 tabular-nums">
            {compact(tick)}
          </span>
        </div>

        <svg
          viewBox={@view_box}
          preserveAspectRatio="none"
          aria-hidden="true"
          class="absolute inset-0 size-full overflow-visible"
        >
          <path
            :for={s <- @series}
            d={s.line}
            data-series={s.n}
            fill="none"
            stroke={s.color}
            stroke-width="2"
            stroke-linejoin="round"
            stroke-linecap="round"
            vector-effect="non-scaling-stroke"
          />
        </svg>

        <div class="absolute inset-0 flex" role="group" aria-label="Games played per day">
          <div
            :for={{day, i} <- Enum.with_index(@days)}
            id={"day-#{day.date}"}
            tabindex="0"
            role="img"
            aria-label={"#{long_date(day.date)}: #{games_label(series_total(day, @series))}"}
            class="group relative h-full flex-1 outline-none"
          >
            <div class="absolute inset-y-0 left-1/2 w-px bg-base-content/25 opacity-0 transition group-hover:opacity-100 group-focus-visible:opacity-100">
            </div>
            <div
              :for={s <- @series}
              :if={games_in(day, s.game) > 0}
              class="absolute left-1/2 size-2.5 -translate-x-1/2 translate-y-1/2 rounded-full opacity-0 ring-2 ring-base-100 transition group-hover:opacity-100 group-focus-visible:opacity-100"
              style={"bottom: #{percent(games_in(day, s.game), @max)}%; background-color: #{s.color}"}
            >
            </div>
            <div class={[
              "pointer-events-none absolute top-0 z-10 w-max min-w-40 rounded-xl bg-base-100 px-3 py-2 shadow-lg ring-1 ring-base-content/10",
              "translate-y-1 opacity-0 transition group-hover:translate-y-0 group-hover:opacity-100 group-focus-visible:translate-y-0 group-focus-visible:opacity-100",
              if(i < @count * 0.6, do: "left-1/2 ml-3", else: "right-1/2 mr-3")
            ]}>
              <p class="text-xs text-base-content/60">{long_date(day.date)}</p>
              <p class="text-lg font-semibold text-octo-navy dark:text-base-content">
                {games_label(series_total(day, @series))}
              </p>
              <ul :if={@series != []} class="mt-1 space-y-0.5 text-xs">
                <li
                  :for={s <- Enum.sort_by(@series, &games_in(day, &1.game), :desc)}
                  class={[
                    "flex items-center gap-1.5",
                    games_in(day, s.game) == 0 && "opacity-50"
                  ]}
                >
                  <span class="h-0.5 w-3 shrink-0 rounded-full" style={"background-color: #{s.color}"}></span>
                  <span class="flex-1 text-base-content/70">{s.game.name}</span>
                  <span class="pl-3 font-semibold text-octo-navy tabular-nums dark:text-base-content">
                    {games_in(day, s.game)}
                  </span>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <div class="mt-2 ml-10 flex text-xs text-base-content/50" aria-hidden="true">
        <div :for={{day, i} <- Enum.with_index(@days)} class="relative h-4 flex-1">
          <span
            :if={rem(@count - 1 - i, 7) == 0}
            class="absolute left-1/2 -translate-x-1/2 whitespace-nowrap"
          >
            {short_date(day.date)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  # The number of the games in a day of the games with a line
  defp series_total(day, series), do: series |> Enum.map(&games_in(day, &1.game)) |> Enum.sum()

  # The number of the games of one kind in a day
  defp games_in(day, game), do: Map.get(day.by_game, game.id, 0)

  # The distance between two horizontal lines: a round number, so that the
  # top line is at the most games of one shown kind in a day or above it
  defp days_step(days, games) do
    most = for(day <- days, game <- games, do: games_in(day, game)) |> Enum.max(fn -> 0 end)
    raw = max(most / @ticks, 1)
    magnitude = 10 ** floor(:math.log10(raw))

    nice = Enum.find([1, 2, 3, 4, 5, 10], &(raw <= &1 * magnitude))

    nice * magnitude
  end

  defp line_path([{x, y} | rest]),
    do: Enum.reduce(rest, "M#{x},#{y}", fn {x, y}, path -> path <> " L#{x},#{y}" end)

  defp percent(value, max), do: value / max * 100

  # A count in a short form, for example 1.2K for 1200
  defp compact(n) when n >= 1000 do
    value = Float.round(n / 1000, 1)
    if value == trunc(value), do: "#{trunc(value)}K", else: "#{value}K"
  end

  defp compact(n), do: Integer.to_string(n)

  defp games_label(1), do: "1 game"
  defp games_label(n), do: "#{n} games"

  defp short_date(date), do: Calendar.strftime(date, "%b %-d")
  defp long_date(date), do: Calendar.strftime(date, "%a, %b %-d")
end
