defmodule OctomoctoWeb.CampaignComponents do
  @moduledoc """
  The parts of the Campaign tab of a settings page that all games with a
  campaign have: the Free play and Campaign tabs, the map of the levels,
  and the call to sign in that covers the map for a guest. The game gives
  the texts, so that each game uses its own translations.
  """
  use OctomoctoWeb, :html

  import OctomoctoWeb.SettingsComponents, only: [option: 1]

  attr :tab, :atom, required: true, doc: ":free, :campaign or :lobby"
  attr :free_path, :string, required: true
  attr :campaign_path, :string, required: true
  attr :free_label, :string, required: true
  attr :campaign_label, :string, required: true
  attr :lobby_path, :string, default: nil, doc: "the path of the Lobby tab, or nil for no tab"
  attr :lobby_label, :string, default: nil
  attr :lobby_count, :integer, default: 0, doc: "the number of games that a player can join"

  @doc """
  The Free play and Campaign tabs, and an optional Lobby tab, as the
  options of a setting. The Lobby tab shows the number of games that a
  player can join, when there are some.
  """
  def mode_tabs(assigns) do
    ~H"""
    <nav id="campaign-tabs" class="flex justify-center">
      <div class="option-slider flex gap-1 rounded-full bg-base-200 p-1">
        <.option id="tab-free" patch={@free_path} selected={@tab == :free}>
          {@free_label}
        </.option>
        <.option id="tab-campaign" patch={@campaign_path} selected={@tab == :campaign}>
          {@campaign_label}
        </.option>
        <.option :if={@lobby_path} id="tab-lobby" patch={@lobby_path} selected={@tab == :lobby}>
          <span class="flex items-center gap-1.5">
            {@lobby_label}
            <span
              :if={@lobby_count > 0}
              id="tab-lobby-count"
              class={[
                "min-w-5 rounded-full px-1.5 text-xs leading-5 font-semibold tabular-nums transition-colors",
                if(@tab == :lobby,
                  do: "bg-white/25 text-white",
                  else: "bg-octo-indigo text-white"
                )
              ]}
            >
              {@lobby_count}
            </span>
          </span>
        </.option>
      </div>
    </nav>
    """
  end

  # The height of a row of the map, and the place of the first row
  @map_row_height 104
  @map_top 40

  attr :levels, :list,
    required: true,
    doc: "each level has its `:level` number, its `:status` and the `:percent` of its best run"

  attr :selected, :integer, required: true
  attr :path, :any, required: true, doc: "a function that gives the path of a level number"
  attr :label, :any, required: true, doc: "a function that gives the name of a level number"
  slot :caption, required: true, doc: "the text under a level, with the level as the argument"
  slot :badge, doc: "an optional `level_badge/1` on a level, with the level as the argument"

  @doc """
  The levels on a winding path. Each level is a circle with a ring that
  shows the best run. The circles are HTML, with a place in percent of the
  width, so that they move with the width but keep their size. The lines
  between them are borders: a solid line after a done level, else a
  dashed one. A narrow map has 3 levels in a row, a wider map 4 (a
  container query, so it depends on the width of the map, not of the
  screen).
  """
  def campaign_map(assigns) do
    ~H"""
    <div id="campaign-map" class="@container w-full">
      <.map_rows
        :for={columns <- [3, 4]}
        columns={columns}
        levels={@levels}
        selected={@selected}
        path={@path}
        label={@label}
        caption={@caption}
        badge={@badge}
        class={if(columns == 3, do: "@sm:hidden", else: "hidden @sm:block")}
      />
    </div>
    """
  end

  attr :columns, :integer, required: true
  attr :levels, :list, required: true
  attr :selected, :integer, required: true
  attr :path, :any, required: true
  attr :label, :any, required: true
  attr :caption, :any, required: true
  attr :badge, :any, required: true
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
          patch={@path.(level.level)}
          label={@label.(level.level)}
          caption={@caption}
          badge={@badge}
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
  attr :label, :string, required: true
  attr :caption, :any, required: true
  attr :badge, :any, required: true
  attr :style, :string, required: true

  defp level_node(assigns) do
    assigns = assign(assigns, percent: assigns.level.percent, ring_length: @ring_length)

    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-current={@selected && "true"}
      aria-label={@label}
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
            class="-mt-0.5 text-[10px] tabular-nums text-base-content/60"
          >
            {@percent}%
          </span>
        </span>
        {render_slot(@badge, @level)}
      </span>
      <span class="mt-0.5 text-xs whitespace-nowrap text-base-content/60">
        {render_slot(@caption, @level)}
      </span>
    </.link>
    """
  end

  attr :locked, :boolean, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  @doc "A small mark at the top right of a level on the map, for example \"3\" for triplets."
  def level_badge(assigns) do
    ~H"""
    <span
      title={@title}
      class={[
        "absolute grid size-4 place-items-center rounded-full bg-base-100 text-[10px] font-semibold ring-1",
        if(@locked,
          do: "top-2 right-2 text-base-content/40 ring-base-content/15",
          else: "top-0 right-0 text-octo-indigo ring-octo-indigo"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  attr :title, :string, required: true
  attr :text, :string, required: true
  attr :button, :string, required: true

  @doc "The call to sign in, on top of the map of a guest."
  def sign_in_overlay(assigns) do
    ~H"""
    <div
      id="campaign-sign-in"
      class="absolute inset-0 z-10 flex items-start justify-center rounded-2xl bg-base-100/60 p-4 pt-24 backdrop-blur-[2px]"
    >
      <div class="max-w-xs rounded-2xl bg-base-100 p-6 text-center shadow-xl ring-1 ring-base-content/10">
        <.icon name="hero-lock-closed" class="size-7 text-octo-indigo" />
        <p class="mt-2 text-lg font-semibold">{@title}</p>
        <p class="mt-1 text-sm text-base-content/60">{@text}</p>
        <.link
          id="campaign-sign-in-link"
          href={~p"/signin"}
          class="mt-4 inline-block rounded-full bg-octo-indigo px-6 py-2.5 font-medium text-white shadow-lg shadow-octo-indigo/25 transition hover:-translate-y-0.5 hover:bg-octo-indigo/90 active:translate-y-0"
        >
          {@button}
        </.link>
      </div>
    </div>
    """
  end
end
