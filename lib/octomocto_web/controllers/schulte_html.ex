defmodule OctomoctoWeb.SchulteHTML do
  use OctomoctoWeb, :html

  embed_templates "schulte_html/*"

  attr :label, :string, required: true
  attr :icon, :string, required: true, doc: "a hero icon name, such as `hero-users`"
  attr :hint, :string, default: nil, doc: "a short explanation of the selected option"
  attr :wide, :boolean, default: false, doc: "true when the options use the full width"
  slot :inner_block, required: true

  @doc "One setting of a new game: the header, and the options in a row below it."
  def setting(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10">
      <.setting_header label={@label} icon={@icon} />
      <div class="mt-3 flex justify-center">
        <div class={["flex gap-1 rounded-full bg-base-200 p-1", @wide && "w-full"]}>
          {render_slot(@inner_block)}
        </div>
      </div>
      <p :if={@hint} class="mt-1.5 text-left text-xs text-base-content/50">{@hint}</p>
    </div>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true

  @doc "The header of a setting: an icon and the label, as in the results lists."
  def setting_header(assigns) do
    ~H"""
    <h3 class="flex items-center gap-2 text-left font-semibold">
      <.icon name={@icon} class="size-4 text-octo-indigo" /> {@label}
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
  attr :title, :string, required: true
  attr :icon, :string, required: true
  attr :icon_class, :string, required: true
  attr :empty, :boolean, required: true
  attr :empty_text, :string, default: nil, doc: "by default, a call to be the first"
  slot :inner_block, required: true
  slot :aside, doc: "shown at the right of the title"

  @doc "A list of results. An empty list has one row with `empty_text`."
  def score_list(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10">
      <%!-- When the aside does not fit next to the title, it goes below it --%>
      <div class="mb-3 flex flex-wrap items-center justify-between gap-x-3 gap-y-1">
        <h3 class="flex items-center gap-2 whitespace-nowrap font-semibold">
          <.icon name={@icon} class={["size-4", @icon_class]} /> {@title}
        </h3>
        <div :if={@aside != []} class="whitespace-nowrap">{render_slot(@aside)}</div>
      </div>
      <ol id={@id} class="-mx-2 space-y-1 text-sm">
        {render_slot(@inner_block)}
        <li :if={@empty} class="px-2 py-2 text-center text-base-content/40">
          {@empty_text || gettext("No games yet — be the first.")}
        </li>
      </ol>
    </div>
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
  slot :inner_block, required: true

  @doc "The time or the score of a result in a pill, as the Finished label in the list of public games."
  def result_pill(assigns) do
    ~H"""
    <span class={[
      "min-w-16 shrink-0 rounded-full px-3 py-1 text-center text-xs font-semibold tabular-nums",
      if(@best,
        do: "bg-amber-500/10 text-amber-700 dark:text-amber-400",
        else: "bg-base-content/5"
      )
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

  @doc "The names of the players of one game, separated by commas."
  def player_list(assigns) do
    ~H"""
    <span :for={{player, index} <- Enum.with_index(@players)}>{if index > 0, do: ", "}{player_name(
      player.user
    )}<span :if={@scores} class="ml-1 tabular-nums text-base-content/60">{gettext("%{score} pts",
      score: player.score
    )}</span><span
      :if={@accuracy}
      class="tabular-nums text-base-content/60"
    > · {@accuracy.(player)}</span></span>
    """
  end

  @doc "Shows the time as minutes, seconds and tenths, for example \"1:05.3\"."
  def format_time(ms) do
    seconds = div(ms, 1000)
    tenths = div(rem(ms, 1000), 100)
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}.#{tenths}"
  end

  # Do not show the full email of a user to other players.
  def player_name(nil), do: gettext("Guest")

  def player_name(%{display_name: display_name})
      when is_binary(display_name) and display_name != "",
      do: display_name

  def player_name(%{name: name}) when is_binary(name) and name != "", do: name
  def player_name(%{telegram_username: username}) when is_binary(username), do: "@" <> username
  def player_name(%{email: email}), do: email |> String.split("@") |> hd()
end
