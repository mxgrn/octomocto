defmodule OctomoctoWeb.SavedSettings do
  @moduledoc """
  The settings pages of the games show the settings that the user or the
  guest chose last (see `Octomocto.GameSettings`), when the page loads
  without settings in its params. Each change of a setting on the page
  saves the settings. A page load with settings in its params does not
  save them.
  """
  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [connected?: 1]

  alias Octomocto.GameSettings

  @doc """
  Gives the params for the settings of the page: the saved settings of the
  game when the page has no `:settings` assign yet and the params have
  none of the `keys`, else the params.
  """
  def params(socket, game, params, keys) do
    with false <- Map.has_key?(socket.assigns, :settings),
         false <- Enum.any?(keys, &Map.has_key?(params, &1)),
         %{} = saved <-
           GameSettings.get(socket.assigns.current_scope, socket.assigns[:guest_id], game) do
      saved
    else
      _ -> params
    end
  end

  @doc """
  Saves the query of the settings page (see `params/4`) for the game, when
  the new `settings` are not the same as the `:settings` assign of the
  socket. The page must already have the assign: the first load of the
  page saves nothing.
  """
  def save_change(socket, game, settings, query) do
    old = socket.assigns[:settings]

    if connected?(socket) and old != nil and old != settings do
      GameSettings.put(
        socket.assigns.current_scope,
        socket.assigns[:guest_id],
        game,
        to_params(query)
      )
    end

    :ok
  end

  @doc """
  Gives the tab of the game page that the user or the guest used last, for
  example "lobby", or nil. It reads the database only once for a socket.
  """
  def last_tab(%{assigns: %{last_tab: {tab}}}, _game), do: tab

  def last_tab(socket, game) do
    GameSettings.get_tab(socket.assigns.current_scope, socket.assigns[:guest_id], game)
  end

  @doc """
  Saves the tab of the game page that the user or the guest opens, once
  the page is connected. Gives the socket with the tab.
  """
  def remember_tab(socket, game, tab) do
    old = last_tab(socket, game)

    if connected?(socket) and (old || "free") != tab do
      GameSettings.put_tab(socket.assigns.current_scope, socket.assigns[:guest_id], game, tab)
      assign(socket, :last_tab, {tab})
    else
      assign(socket, :last_tab, {old})
    end
  end

  @doc "Gives the params of a query of the settings page, as strings."
  def to_params(query),
    do: Map.new(query, fn {key, value} -> {to_string(key), to_string(value)} end)
end
