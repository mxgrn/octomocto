defmodule OctomoctoWeb.StatsLive do
  @moduledoc """
  The page with the number of games played in each of the last days. A
  LiveView, so that a click on a game in the legend of the chart adds or
  removes its line, and the chart fits the lines that stay.

  All stats pages show the 30 days before today, because the counts of today
  are not complete. The "Include today" toggle (`today_toggle/1`) adds
  `?today=1` to the URL, and then the pages show the last 30 days with
  today. The links between the stats pages keep the toggle.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.Stats
  alias OctomoctoWeb.{GameIcons, HomeLive, PlayerLive}

  # The number of days of all stats pages
  @days 30

  # The size of the SVG coordinates of the chart. The SVG stretches to the
  # size of the plot, so only the proportions of the values are important.
  @width 1000
  @height 200

  # The number of horizontal lines above the zero line
  @ticks 4

  # The number of line colors, `--series-1` to `--series-10` in `app.css`
  @colors 10

  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "30-day stats", noindex: true, hidden: MapSet.new())}
  end

  def handle_params(params, _uri, socket) do
    today? = today?(params)
    {count, last} = period(today?)
    days = Stats.games_per_day(count, last)

    {:noreply,
     assign(socket,
       today?: today?,
       days: days,
       total: days |> Enum.map(& &1.total) |> Enum.sum(),
       today_total: if(today?, do: List.last(days), else: hd(Stats.games_per_day(1))).total,
       by_game: games_by_count(days),
       by_language: Stats.games_by_language(count, last)
     )}
  end

  def handle_event("toggle_game", %{"id" => id}, socket) do
    hidden = socket.assigns.hidden

    hidden =
      if MapSet.member?(hidden, id), do: MapSet.delete(hidden, id), else: MapSet.put(hidden, id)

    {:noreply, assign(socket, hidden: hidden)}
  end

  @doc "True when the URL `params` of a stats page include today."
  def today?(params), do: params["today"] == "1"

  @doc """
  The days of the stats pages as `{count, last day}`: the last #{@days} days
  with today, or the #{@days} days before today without it.
  """
  def period(true = _today?), do: {@days, Date.utc_today()}
  def period(false), do: {@days, Date.add(Date.utc_today(), -1)}

  @doc "The `path` of a stats page, with `?today=1` when it includes today."
  def stats_path(path, true = _today?), do: path <> "?today=1"
  def stats_path(path, false), do: path

  @doc "The days of the stats pages in a sentence, for example \"the last 30 days\"."
  def period_text(true = _today?), do: "the last #{@days} days"
  def period_text(false), do: "the #{@days} days before today"

  @doc "The days of the stats pages as a short label, for example \"Last 30 days\"."
  def period_label(true = _today?), do: "Last #{@days} days"
  def period_label(false), do: "#{@days} days before today"

  @doc """
  Renders the "Include today" switch of the stats pages. A click patches
  the page to the URL with the other state of the switch.
  """
  attr :on, :boolean, required: true, doc: "true when the page includes today"
  attr :path, :string, required: true, doc: "the path of the page, without `?today=1`"

  def today_toggle(assigns) do
    ~H"""
    <.link
      id="include-today"
      patch={stats_path(@path, not @on)}
      replace
      role="switch"
      aria-checked={to_string(@on)}
      class="group inline-flex shrink-0 items-center gap-2 rounded-full py-1 text-sm text-base-content/70 transition hover:text-base-content"
    >
      <span class={[
        "relative h-5 w-9 rounded-full transition-colors duration-200",
        if(@on,
          do: "bg-octo-indigo dark:bg-octo-indigo-light",
          else: "bg-base-content/20 group-hover:bg-base-content/30"
        )
      ]}>
        <span class={[
          "absolute top-0.5 left-0.5 size-4 rounded-full bg-white shadow-sm transition-transform duration-200",
          @on && "translate-x-4"
        ]}></span>
      </span>
      Include today
    </.link>
    """
  end

  # The games of the front page with their counts in each day and their
  # totals for all days, the most played first
  defp games_by_count(days) do
    HomeLive.games()
    |> Enum.map(fn game ->
      counts = Enum.map(days, &games_in(&1, game))
      game |> Map.put(:days, counts) |> Map.put(:count, Enum.sum(counts))
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Renders a line chart with one line for each game, as in Google Analytics.
  A pointer on a day (or the keyboard focus) shows a vertical line, a dot on
  each game with games in the day, and the counts of all games in the day.
  Each game has a fixed color (see `--series-1` to `--series-10` in
  `app.css`), in the order of the games, the most played first. After the
  tenth game the colors start again, so the games with the same color are
  far apart in the number of games. A click on a
  game in the legend sends `toggle_game` with the id of the game. The
  hidden games have no line, and the y-axis fits the other games. A pointer
  on a shown game in the legend (or the keyboard focus) makes the lines of
  the other games pale (see `#games-chart` in `app.css`). The first item of
  the legend is the total: a line with the sum of the shown games in each
  day. A click on it sends `toggle_game` with the id `"total"`. When the
  total line is shown, the y-axis fits it.
  """
  attr :days, :list, required: true, doc: "the days of `Octomocto.Stats.games_per_day/2`"
  attr :games, :list, required: true, doc: "the games of the front page, the most played first"

  attr :hidden, :any,
    required: true,
    doc: ~s|the ids of the games without a line, and "total" without the total line, a MapSet|

  def games_chart(assigns) do
    visible = Enum.reject(assigns.games, &MapSet.member?(assigns.hidden, &1.id))
    total? = not MapSet.member?(assigns.hidden, "total")
    totals = Enum.map(assigns.days, fn day -> Enum.sum_by(visible, &games_in(day, &1)) end)

    counts =
      for(day <- assigns.days, game <- visible, do: games_in(day, game)) ++
        if total?, do: totals, else: []

    step = days_step(counts)
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

        %{game: game, n: n, color: series_color(n), line: line_path(points)}
      end)

    total_line =
      if total? do
        totals
        |> Enum.with_index()
        |> Enum.map(fn {total, i} ->
          {(i + 0.5) * @width / count, @height - total / max * @height}
        end)
        |> line_path()
      end

    assigns =
      assign(assigns,
        max: max,
        ticks: Enum.map(0..@ticks, &(&1 * step)),
        count: count,
        series: series,
        total?: total?,
        total_line: total_line,
        colors: Enum.with_index(assigns.games, 1),
        view_box: "0 0 #{@width} #{@height}"
      )

    ~H"""
    <div id="games-chart" class="select-none">
      <ul id="games-legend" class="mt-6 -ml-2 flex flex-wrap gap-1 text-xs">
        <li>
          <button
            id="legend-total"
            type="button"
            phx-click="toggle_game"
            phx-value-id="total"
            data-legend="total"
            aria-pressed={to_string(@total?)}
            class={[
              "flex items-center gap-1.5 rounded-full px-2 py-1 font-medium transition",
              "text-base-content/70 hover:bg-base-200 hover:text-base-content active:scale-95",
              "aria-[pressed=false]:text-base-content/35 aria-[pressed=false]:line-through"
            ]}
          >
            <span class="h-0.5 w-3 rounded-full bg-current transition"></span> Total
          </button>
        </li>
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
                  else: "background-color: #{series_color(n)}"
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
          <path
            :if={@total?}
            d={@total_line}
            data-series="total"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-dasharray="4 4"
            stroke-opacity="0.6"
            stroke-linejoin="round"
            stroke-linecap="round"
            vector-effect="non-scaling-stroke"
            class="text-octo-navy dark:text-base-content"
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
              :if={@total? and series_total(day, @series) > 0}
              class="absolute left-1/2 size-2.5 -translate-x-1/2 translate-y-1/2 rounded-full bg-octo-navy opacity-0 ring-2 ring-base-100 transition group-hover:opacity-100 group-focus-visible:opacity-100 dark:bg-base-content"
              style={"bottom: #{percent(series_total(day, @series), @max)}%"}
            >
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

  # The color of the line of the game `n` of the legend
  defp series_color(n), do: "var(--series-#{rem(n - 1, @colors) + 1})"

  # The number of the games in a day of the games with a line
  defp series_total(day, series), do: series |> Enum.map(&games_in(day, &1.game)) |> Enum.sum()

  # The number of the games of one kind in a day
  defp games_in(day, game), do: Map.get(day.by_game, game.id, 0)

  # The distance between two horizontal lines: a round number, so that the
  # top line is at the largest of the counts or above it
  defp days_step(counts) do
    most = Enum.max(counts, fn -> 0 end)
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
