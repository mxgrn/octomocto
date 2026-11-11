defmodule OctomoctoWeb.BestResults do
  @moduledoc """
  The "Best results" list of a game page, with a filter for a signed-in
  user: all players, or only the players that the user follows and the
  user (see `Octomocto.Friends`).

  A LiveView uses the hook, and assigns the list with the game context and
  the settings of the results:

      on_mount OctomoctoWeb.BestResults

      socket |> BestResults.assign_best(Snap, filter)

  The context must have `best_results(settings, user_ids)`. The hook
  handles the clicks of `filter/1` and assigns `:best_results` again.
  """
  use OctomoctoWeb, :html

  import Phoenix.LiveView, only: [attach_hook: 4]

  alias Octomocto.Friends

  def on_mount(:default, _params, _session, socket) do
    {:cont,
     socket
     |> assign(best_following: false, best_query: nil)
     |> attach_hook(:best_results, :handle_event, &handle_event/3)}
  end

  @doc """
  Assigns `:best_results` from `context.best_results(settings, user_ids)`,
  with the filter that the user chose on this page.
  """
  def assign_best(socket, context, settings) do
    socket
    |> assign(:best_query, {context, settings})
    |> assign_list()
  end

  defp handle_event("best_results_filter", %{"following" => following}, socket) do
    {:halt, socket |> assign(:best_following, following == "true") |> assign_list()}
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  defp assign_list(socket) do
    {context, settings} = socket.assigns.best_query
    assign(socket, :best_results, context.best_results(settings, user_ids(socket)))
  end

  # Nil gives the results of all players. A guest has no filter.
  defp user_ids(%{assigns: %{best_following: true, current_scope: %{user: %{id: id}}}}),
    do: [id | Friends.followed_ids(id)]

  defp user_ids(_socket), do: nil

  attr :following, :boolean, required: true

  @doc "The two buttons of the filter: All and Following."
  def filter(assigns) do
    ~H"""
    <OctomoctoWeb.SettingsComponents.option_slider
      id="best-results-filter"
      light
      class="items-center text-xs font-medium"
    >
      <button
        :for={{following, label} <- [{false, gettext("All")}, {true, gettext("Following")}]}
        id={if following, do: "best-results-following", else: "best-results-all"}
        type="button"
        phx-click="best_results_filter"
        phx-value-following={to_string(following)}
        aria-pressed={to_string(following == @following)}
        aria-current={following == @following && "true"}
        class={[
          "rounded-full px-2.5 py-1 transition-colors",
          if(following == @following,
            do: "bg-white text-base-content shadow-sm dark:bg-white/12",
            else: "cursor-pointer text-base-content/60 hover:text-base-content"
          )
        ]}
      >
        {label}
      </button>
    </OctomoctoWeb.SettingsComponents.option_slider>
    """
  end

  @doc """
  The path of the settings page of the `game` (the game id of the front
  page) that shows the Best results of the `settings` of the results.
  The page takes only the params, not the settings that the user saved.
  """
  def path(game, settings), do: "/#{game}?" <> URI.encode_query(params(game, settings))

  defp params("snap", %{"back" => back}), do: [back: back]
  defp params("mahjong", %{"players" => players}), do: [players: players]
  defp params("overlap", %{"players" => players}), do: [players: players]
  defp params("graze", %{"players" => players}), do: [players: players]
  defp params("echo", s), do: [pads: s["pads"], players: s["players"]]
  defp params("set", s), do: [players: s["players"], mode: s["mode"]]
  defp params("sudoku", s), do: [players: s["players"], difficulty: s["difficulty"]]

  defp params("afterglow", %{"players" => 1}), do: [players: 1]
  defp params("afterglow", s), do: [players: s["players"], size: s["size"]]

  defp params("nimble-mosaic", s),
    do: [board: s["type"], mode: s["mode"], players: s["players"]]

  defp params("schulte", s),
    do: [size: s["size"], marks: if(s["marks"], do: "on", else: "off"), players: s["players"]]

  defp params("memory", s) do
    set = if s["set"] == 3, do: "triplets", else: "pairs"
    params = [set: set, cards: s["cards"], players: s["players"]]
    if s["bombs"], do: params ++ [bombs: s["bombs"]], else: params
  end

  defp params("trains", s) do
    [
      players: s["players"],
      switches: s["switch_count"],
      trains: s["trains_per_house"],
      pace: s["pace"]
    ]
  end

  @doc "The text of an empty list, by the filter."
  def empty_text(true), do: gettext("No results of you and the players you follow.")
  def empty_text(false), do: nil
end
