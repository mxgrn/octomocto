defmodule OctomoctoWeb.MatchHTML do
  use OctomoctoWeb, :html

  # The same settings and result lists as on the Schulte page
  import OctomoctoWeb.SchulteHTML,
    only: [setting: 1, score_list: 1, player_list: 1, format_time: 1, player_name: 1]

  embed_templates "match_html/*"

  attr :id, :string, required: true
  attr :href, :string, required: true
  attr :selected, :boolean, required: true
  slot :inner_block, required: true

  def option(assigns) do
    ~H"""
    <.link
      id={@id}
      href={@href}
      aria-current={@selected && "true"}
      class={[
        "min-w-10 rounded-full px-4 py-1.5 text-sm font-medium transition",
        if(@selected,
          do: "bg-sky-600 text-white shadow-sm",
          else: "text-base-content/70 hover:bg-base-100 hover:text-base-content"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  attr :id, :string, required: true
  attr :href, :string, default: nil, doc: "nil when the button does nothing"
  attr :icon, :string, required: true
  attr :label, :string, required: true

  @doc "A round button that makes the number of cards smaller or larger."
  def step_button(assigns) do
    ~H"""
    <.link
      :if={@href}
      id={@id}
      href={@href}
      aria-label={@label}
      class="grid size-9 place-items-center rounded-full text-base-content/70 transition hover:bg-base-100 hover:text-base-content active:scale-90"
    >
      <.icon name={@icon} class="size-4" />
    </.link>
    <span
      :if={!@href}
      id={@id}
      aria-disabled="true"
      class="grid size-9 place-items-center rounded-full text-base-content/20"
    >
      <.icon name={@icon} class="size-4" />
    </span>
    """
  end

  @doc "The query of the index page for the settings, with some of them changed."
  def query(settings, changes \\ []) do
    settings = Map.merge(settings, Map.new(changes))

    [
      theme: settings.theme,
      set: if(settings.set == 3, do: "triplets", else: "pairs"),
      cards: settings.cards,
      players: settings.players
    ]
  end

  @doc "The possible size before (-1) or after (1) the current one, or nil."
  def step_size(sizes, cards, -1), do: sizes |> Enum.filter(&(&1 < cards)) |> List.last()
  def step_size(sizes, cards, 1), do: Enum.find(sizes, &(&1 > cards))
end
