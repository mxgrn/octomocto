defmodule OctomoctoWeb.OnlineUsers do
  @moduledoc """
  The `on_mount` hook that tracks a signed-in user on each LiveView page
  (see `Octomocto.OnlineUsers`). The settings page of a game has the id of
  the game as its kind.
  """
  alias OctomoctoWeb.{
    AfterglowLive,
    EchoLive,
    MahjongLive,
    MemoryLive,
    OverlapLive,
    NimbleMosaicLive,
    SetGameLive,
    SnapLive,
    SudokuLive,
    TrainsLive
  }

  @kinds %{
    AfterglowLive => "afterglow",
    EchoLive => "echo",
    MahjongLive => "mahjong",
    MemoryLive => "memory",
    OverlapLive => "overlap",
    NimbleMosaicLive => "nimble-mosaic",
    SetGameLive => "set",
    SnapLive => "snap",
    SudokuLive => "sudoku",
    TrainsLive => "trains"
  }

  def on_mount(:default, _params, _session, socket) do
    with true <- Phoenix.LiveView.connected?(socket),
         %{user: %{id: user_id}} <- socket.assigns[:current_scope] do
      kind = @kinds[socket.view]
      doing = if kind, do: "settings"
      Octomocto.OnlineUsers.track(self(), user_id, %{kind: kind, doing: doing})
    end

    {:cont, socket}
  end
end
