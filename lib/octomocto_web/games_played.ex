defmodule OctomoctoWeb.GamesPlayed do
  @moduledoc """
  The `on_mount` hook that assigns the number of all games played in
  `:games_played`, for the footer (see `OctomoctoWeb.Layouts.app/1`). The
  number comes from memory (see `Octomocto.Stats.Counter`) and goes up live:
  each finished game adds one.

  A controller page does not use it: there, the footer reads the number from
  memory once.
  """
  import Phoenix.Component, only: [assign: 3, update: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Octomocto.Stats

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket), do: Stats.subscribe()

    {:cont,
     socket
     |> assign(:games_played, Stats.Counter.get())
     |> attach_hook(:games_played, :handle_info, &handle_info/2)}
  end

  defp handle_info({:game_finished}, socket),
    do: {:halt, update(socket, :games_played, &(&1 + 1))}

  defp handle_info(_message, socket), do: {:cont, socket}
end
