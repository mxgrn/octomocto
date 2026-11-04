defmodule OctomoctoWeb.GameBarLive do
  @moduledoc """
  The thin bar at the top of a game page. The game controller renders it
  with `live_render/3`, with the `"kind"` (an id in
  `OctomoctoWeb.HomeLive.games/0`), the `"id"` of the game and the
  `"locale"` of the page in the session.

  It shows the first notice of the user or the guest, if any (see
  `OctomoctoWeb.Notices`). Else it shows the settings of the game, as the
  rows of the lists of public games do (see `game_summary/1` of each
  settings page), the number of players and the visibility. A game with
  no lists, such as a single-player game, shows no settings. The bar has a
  fixed height, so that a notice does not move the game.

  It subscribes to the topic of the game and reads the game from its store
  again after each message, so that a change of the settings between two
  fields of a match shows at once.
  """
  use OctomoctoWeb, :live_view

  alias OctomoctoWeb.HomeLive

  on_mount {OctomoctoWeb.UserAuth, :mount_current_scope}
  on_mount OctomoctoWeb.GuestName
  on_mount OctomoctoWeb.Notices

  def mount(_params, %{"kind" => kind, "id" => id, "locale" => locale}, socket) do
    Gettext.put_locale(OctomoctoWeb.Gettext, locale)

    socket =
      case HomeLive.lobby_modules(kind) do
        {game, store, page} ->
          if connected?(socket), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, game.topic(id))

          socket
          |> assign(id: id, game: game, store: store, page: page)
          |> assign_game()

        nil ->
          assign(socket, state: nil)
      end

    {:ok, socket, layout: false}
  end

  # Any change of the game
  def handle_info(_message, socket), do: {:noreply, assign_game(socket)}

  # The state is nil when the game stopped
  defp assign_game(%{assigns: %{id: id, store: store}} = socket) do
    assign(socket, state: store.read(id))
  end

  def render(assigns) do
    ~H"""
    <div
      id="game-bar"
      class={[
        "flex h-8 items-center justify-center px-4 text-xs transition-colors",
        if(@notices != [], do: "bg-octo-indigo text-white", else: "text-base-content/60")
      ]}
    >
      <%= cond do %>
        <% @notices != [] -> %>
          <OctomoctoWeb.Notices.notice notice={hd(@notices)} waiting={length(@notices) - 1} />
        <% @state -> %>
          <p id="game-bar-summary" class="truncate">
            <%= if summary = @page.game_summary(%{id: @id, settings: @game.lobby_settings(@state)}) do %>
              {summary} ·
            <% end %>
            {players(@state.needed)} · {visibility(@state)}
          </p>
        <% true -> %>
      <% end %>
    </div>
    """
  end

  defp players(1), do: gettext("Solo")
  defp players(n), do: ngettext("%{count} player", "%{count} players", n)

  defp visibility(%{public: true}), do: gettext("Public")
  defp visibility(_state), do: gettext("Private link")
end
