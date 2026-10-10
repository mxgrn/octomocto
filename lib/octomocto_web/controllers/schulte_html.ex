defmodule OctomoctoWeb.SchulteHTML do
  use OctomoctoWeb, :html

  embed_templates "schulte_html/*"

  attr :label, :string, required: true
  attr :hint, :string, default: nil, doc: "a short explanation of the selected option"
  slot :inner_block, required: true

  @doc "One setting of a new game, with its options in a row."
  def setting(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 px-4 py-2.5 ring-1 ring-base-content/10">
      <div class="flex items-center justify-between gap-4">
        <span class="text-sm font-medium text-base-content/60">{@label}</span>
        <div class="flex gap-1 rounded-full bg-base-200 p-1">
          {render_slot(@inner_block)}
        </div>
      </div>
      <p :if={@hint} class="mt-1.5 text-left text-xs text-base-content/50">{@hint}</p>
    </div>
    """
  end

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
          do: "bg-emerald-600 text-white shadow-sm",
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
  slot :inner_block, required: true
  slot :aside, doc: "shown at the right of the title"

  @doc "A list of results. An empty list has one row with \"---\"."
  def score_list(assigns) do
    ~H"""
    <div class="rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10">
      <div class="mb-3 flex items-center justify-between gap-3">
        <h3 class="flex items-center gap-2 font-semibold">
          <.icon name={@icon} class={["size-4", @icon_class]} /> {@title}
        </h3>
        {render_slot(@aside)}
      </div>
      <ol id={@id} class="divide-y divide-base-content/5 text-sm">
        {render_slot(@inner_block)}
        <li :if={@empty} class="py-2 text-center text-base-content/40">---</li>
      </ol>
    </div>
    """
  end

  @doc "Shows the time as minutes, seconds and tenths, for example \"1:05.3\"."
  def format_time(ms) do
    seconds = div(ms, 1000)
    tenths = div(rem(ms, 1000), 100)
    "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}.#{tenths}"
  end

  # Do not show the full email of a user to other players.
  def player_name(nil), do: "Guest"

  def player_name(%{display_name: display_name})
      when is_binary(display_name) and display_name != "",
      do: display_name

  def player_name(%{name: name}) when is_binary(name) and name != "", do: name
  def player_name(%{telegram_username: username}) when is_binary(username), do: "@" <> username
  def player_name(%{email: email}), do: email |> String.split("@") |> hd()
end
