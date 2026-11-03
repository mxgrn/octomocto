defmodule OctomoctoWeb.SavedSettings do
  @moduledoc """
  The settings pages of the games show the settings that the user or the
  guest chose last (see `Octomocto.GameSettings`), when the page loads
  without settings in its params. Each change of a setting on the page
  saves the settings. A page load with settings in its params does not
  save them.
  """
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

  @doc "Gives the params of a query of the settings page, as strings."
  def to_params(query),
    do: Map.new(query, fn {key, value} -> {to_string(key), to_string(value)} end)
end
