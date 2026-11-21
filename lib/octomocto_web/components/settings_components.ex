defmodule OctomoctoWeb.SettingsComponents do
  @moduledoc """
  The parts of the settings page of each game: the settings with their
  options, and the lists of results.
  """
  use OctomoctoWeb, :html

  attr :id, :string, required: true
  attr :label, :string, required: true
  attr :icon, :string, required: true, doc: "an icon name, such as `hero-users` (see `icon/1`)"
  attr :hint, :string, default: nil, doc: "a short explanation of the selected option"
  attr :wide, :boolean, default: false, doc: "true when the options use the full width"
  attr :badge, :string, default: nil, doc: "a text such as \"New\" next to the label"
  attr :badge_id, :string, default: nil
  slot :inner_block, required: true

  @doc "One setting of a new game: the header, and the options in a row below it."
  def setting(assigns) do
    ~H"""
    <div
      id={@id}
      class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-base-content/10 dark:bg-base-100"
    >
      <.setting_header label={@label} icon={@icon} badge={@badge} badge_id={@badge_id} />
      <div class="mt-3 flex justify-center">
        <.option_slider id={"#{@id}-options"} class={@wide && "w-full"}>
          {render_slot(@inner_block)}
        </.option_slider>
      </div>
      <p :if={@hint} class="mt-1.5 text-start text-xs text-base-content/50">{@hint}</p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :any, default: nil

  attr :light, :boolean,
    default: false,
    doc: "true for a small row, as the filter of the best results"

  slot :inner_block, required: true

  @doc """
  A row of `option/1`s with one pill that slides to the selected option.

  The hook measures the selected option and gives its place to the pill
  in CSS variables (see `.option-slider` in app.css). Before the hook
  runs, the selected option shows its own background. The hook measures
  again after each update, and when the size of the row or of an option
  changes, for example when a font loads or the screen turns.
  """
  def option_slider(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook=".OptionSlider"
      class={[
        "option-slider flex rounded-full",
        if(@light,
          do: "option-slider-light gap-0.5 bg-base-200/70 p-0.5",
          else: "gap-1 bg-base-200 p-1"
        ),
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".OptionSlider">
      export default {
        mounted() {
          // Keep the place of the pill when LiveView patches the row
          this.js().ignoreAttributes(this.el, ["style", "data-slider-ready"])
          this.observer = new ResizeObserver(() => this.place(false))
          this.observe()
          this.place(false)
        },
        updated() {
          this.place(true)
          this.observe()
        },
        destroyed() {
          this.observer.disconnect()
        },
        observe() {
          // Observing an element again has no effect
          this.observer.observe(this.el)
          for (const option of this.el.children) this.observer.observe(option)
        },
        place(slide) {
          const option = this.el.querySelector("[aria-current]")
          if (!option) {
            // The next selected option gets the pill without a slide
            this.last = null
            return
          }
          // A hidden row has no size. The observer calls again when it shows.
          if (option.offsetWidth === 0) return

          const x = option.offsetLeft
          const y = option.offsetTop
          const width = option.offsetWidth
          const height = option.offsetHeight
          const key = `${x} ${y} ${width} ${height}`
          if (key === this.last) return
          const instant = !slide || this.last === null || this.last === undefined
          this.last = key

          const style = this.el.style
          if (instant) style.setProperty("--pill-transition", "none")
          style.setProperty("--pill-x", `${x}px`)
          style.setProperty("--pill-y", `${y}px`)
          style.setProperty("--pill-width", `${width}px`)
          style.setProperty("--pill-height", `${height}px`)
          this.el.dataset.sliderReady = ""
          if (instant) {
            // Apply the place without a transition, then allow transitions again
            this.el.offsetWidth
            style.removeProperty("--pill-transition")
          }
        }
      }
    </script>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :badge, :string, default: nil, doc: "a text such as \"New\" next to the label"
  attr :badge_id, :string, default: nil

  @doc "The header of a setting: an icon and the label, as in the results lists."
  def setting_header(assigns) do
    ~H"""
    <h3 class="flex items-center gap-2 text-start font-semibold">
      <.icon name={@icon} class="size-4 text-octo-indigo" /> {@label}
      <%!-- In the brand orange, so that it stands out from the indigo --%>
      <span
        :if={@badge}
        id={@badge_id}
        class="rounded-full bg-octo-orange px-1.5 py-0.5 text-[10px] leading-none font-semibold tracking-wide text-white uppercase shadow-sm"
      >
        {@badge}
      </span>
    </h3>
    """
  end

  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :selected, :boolean, required: true
  slot :inner_block, required: true

  @doc "One option of a setting. A click changes the settings in the URL without a page load."
  def option(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      class={[
        "min-w-10 rounded-full px-4 py-1.5 text-sm font-medium transition",
        if(@selected,
          do: "cursor-default bg-white text-base-content shadow-sm dark:bg-white/12",
          else: "text-base-content/70 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :icon_class, :string, required: true
  attr :empty, :boolean, required: true
  attr :empty_text, :string, default: nil, doc: "by default, a call to be the first"
  slot :inner_block, required: true
  slot :aside, doc: "shown at the right of the title"
  slot :chart, doc: "shown below the title, for example a `sparkline/1`"

  attr :sign_in, :string,
    default: nil,
    doc: "for a guest, the sign-in path: the chart and the list are a blurred preview"

  attr :preview_key, :any,
    default: nil,
    doc: "changes when the preview must change, see `OctomoctoWeb.ResultsPreview`"

  @doc """
  A list of results. An empty list has one row with `empty_text`.

  With `sign_in`, the chart and the list are blurred under a call to sign
  in. The page keeps them from the first render, so a random preview does
  not change when the LiveView connects.
  """
  def score_list(assigns) do
    ~H"""
    <div class="rounded-2xl bg-white p-5 shadow-sm ring-1 ring-base-content/10 dark:bg-base-100">
      <%!-- When the aside does not fit next to the title, it goes below it --%>
      <div class="mb-3 flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <h3 class="flex items-center gap-2 whitespace-nowrap font-semibold">
          <.icon name={@icon} class={["size-4", @icon_class]} /> {@title}
        </h3>
        <div :if={@aside != []} class="whitespace-nowrap">{render_slot(@aside)}</div>
      </div>
      <div
        id={@sign_in && "#{@id}-preview-#{@preview_key}"}
        phx-update={@sign_in && "ignore"}
        class={@sign_in && "relative"}
      >
        <div
          aria-hidden={@sign_in && "true"}
          inert={@sign_in != nil}
          class={@sign_in && "pointer-events-none select-none opacity-60 blur-[3px]"}
        >
          {render_slot(@chart)}
          <ol id={@id} class="-mx-2 space-y-1 text-sm">
            {render_slot(@inner_block)}
            <li :if={@empty} class="px-2 py-2 text-center text-base-content/40">
              {@empty_text || gettext("No games yet — be the first.")}
            </li>
          </ol>
        </div>
        <div :if={@sign_in} class="absolute inset-0 flex items-center justify-center">
          <.link
            id={"#{@id}-sign-in"}
            href={@sign_in}
            class="flex items-center gap-2 rounded-full bg-octo-indigo px-5 py-2.5 text-sm font-semibold text-white shadow-lg shadow-octo-indigo/25 transition hover:bg-octo-indigo/90 hover:shadow-xl active:scale-[0.98]"
          >
            <.icon name="hero-lock-closed" class="size-4" />
            {gettext("Sign in to see your progress")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :points, :list, required: true, doc: "`%{id: id, value: value}` items, the oldest first"
  attr :best, :map, default: nil, doc: "the best result, shown in amber when it is a point"
  attr :lower_better, :boolean, default: false, doc: "true for times: a lower value is higher"

  @doc """
  A line of the latest results, where higher is always better. It shows
  nothing with fewer than 3 points.
  """
  def sparkline(assigns) do
    assigns =
      assigns
      |> assign(:dots, sparkline_dots(assigns.points, assigns.lower_better))
      |> assign(:best_id, assigns.best && assigns.best.id)

    ~H"""
    <div :if={length(@dots) >= 3} id={@id} class="relative mb-3 h-12" aria-hidden="true">
      <svg
        viewBox="0 0 100 100"
        preserveAspectRatio="none"
        class="absolute inset-0 size-full overflow-visible text-octo-indigo"
      >
        <defs>
          <linearGradient id={"#{@id}-fill"} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stop-color="currentColor" stop-opacity="0.18" />
            <stop offset="1" stop-color="currentColor" stop-opacity="0" />
          </linearGradient>
        </defs>
        <polygon points={"0,100 #{sparkline_path(@dots)} 100,100"} fill={"url(##{@id}-fill)"} />
        <polyline
          points={sparkline_path(@dots)}
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linejoin="round"
          stroke-linecap="round"
          vector-effect="non-scaling-stroke"
        />
      </svg>
      <span
        :for={dot <- @dots}
        :if={dot.id == @best_id or dot.latest}
        data-best={dot.id == @best_id}
        data-latest={dot.latest}
        class={[
          "absolute size-2 -translate-1/2 rounded-full ring-2 ring-white dark:ring-base-100",
          if(dot.id == @best_id, do: "bg-amber-500", else: "bg-octo-indigo")
        ]}
        style={"left: #{dot.x}%; top: #{dot.y}%"}
      />
    </div>
    """
  end

  # Places the points in a 100 × 100 box with some space at the top and
  # the bottom, the best value at the top.
  defp sparkline_dots(points, lower_better) do
    values = Enum.map(points, & &1.value)
    {low, high} = if values == [], do: {0, 0}, else: Enum.min_max(values)
    last = length(points) - 1

    points
    |> Enum.with_index()
    |> Enum.map(fn {point, index} ->
      share = if high == low, do: 0.5, else: (point.value - low) / (high - low)
      share = if lower_better, do: 1 - share, else: share

      %{
        id: point.id,
        latest: index == last,
        x: Float.round(index / max(last, 1) * 100, 2),
        y: Float.round(90 - share * 80, 2)
      }
    end)
  end

  defp sparkline_path(dots), do: Enum.map_join(dots, " ", &"#{&1.x},#{&1.y}")

  attr :rows, :list, required: true, doc: "the `:latest` of an `OctomoctoWeb.ResultsPreview`"
  attr :best, :map, required: true
  attr :format, :any, required: true, doc: "a function that formats a value"

  @doc "The rows of a made-up list of results for a guest, see `OctomoctoWeb.ResultsPreview`."
  def preview_rows(assigns) do
    ~H"""
    <.result_row :for={row <- @rows}>
      <span class="flex-1 font-medium">{OctomoctoWeb.Locale.short_date(row.inserted_at)}</span>
      <.result_pill best={row.id == @best.id}>{@format.(row.value)}</.result_pill>
    </.result_row>
    """
  end

  attr :rest, :global
  slot :inner_block, required: true

  @doc "A row of a `score_list/1`, as a row of the list of public games."
  def result_row(assigns) do
    ~H"""
    <li
      class="flex items-center gap-3 rounded-xl px-2 py-2 transition-colors hover:bg-base-200/60"
      {@rest}
    >
      {render_slot(@inner_block)}
    </li>
    """
  end

  attr :best, :boolean, default: false, doc: "the best result of the user, in amber"

  attr :champion, :boolean,
    default: false,
    doc: "the user completed all the levels of a campaign: solid gold, also for the user"

  slot :inner_block, required: true

  @doc "The time or the score of a result in a pill, as the Finished label in the list of public games."
  def result_pill(assigns) do
    ~H"""
    <span class={[
      "min-w-16 shrink-0 rounded-full px-3 py-1 text-center text-xs font-semibold tabular-nums",
      cond do
        @champion -> "bg-amber-400 text-amber-950"
        @best -> "bg-amber-500/10 text-amber-700 dark:text-amber-400"
        true -> "bg-base-content/5"
      end
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :players, :list, required: true, doc: "the results of the players of one game"
  attr :scores, :boolean, required: true, doc: "shows the points next to each player"

  attr :accuracy, :any,
    default: nil,
    doc: "a function that gives the accuracy text of a player, shown after the points"

  @doc """
  The players of one game, one line for each player. A long name is cut,
  the points and the accuracy always show.
  """
  def player_list(assigns) do
    ~H"""
    <span class="flex flex-col">
      <span :for={player <- @players} class="flex min-w-0 items-baseline">
        <.player_link player={player.user || player.guest} class="truncate">
          {result_name(player)}
        </.player_link>
        <span :if={@scores} class="ms-1 shrink-0 tabular-nums text-base-content/60">
          {gettext("%{score} pts", score: player.score)}
        </span>
        <span :if={@accuracy} class="ms-1 shrink-0 tabular-nums text-base-content/60">
          · {@accuracy.(player)}
        </span>
      </span>
    </span>
    """
  end

  @doc "Shows the time as minutes, seconds and tenths, for example \"1:05.3\"."
  def format_time(ms) do
    seconds = div(ms, 1000)
    tenths = div(rem(ms, 1000), 100)
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}.#{tenths}"
  end

  # The same name as in the games
  def player_name(nil), do: gettext("Guest")
  def player_name(user), do: Octomocto.Accounts.public_name(user) || gettext("Guest")

  # A guest from before the guest names is "Guest"
  defp result_name(%{user: nil, guest: %{name: name}}), do: name
  defp result_name(result), do: player_name(result.user)
end
