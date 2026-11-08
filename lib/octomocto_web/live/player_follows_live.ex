defmodule OctomoctoWeb.PlayerFollowsLive do
  @moduledoc """
  The followers of a user, at `/players/:public_id/followers`, and the
  users that the user follows, at `/players/:public_id/following`. Anyone
  can open them. A guest cannot follow, thus has no such pages.

  Each row shows the relation of the viewer to the player in the row: a
  "Follows you" tag and a Follow, Follow back or Following (unfollow)
  button. A row shows the online state and the activity only when the
  player is a friend of the viewer: presence is for friends only (see
  `Octomocto.OnlineUsers`).
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteBanners, nil}

  alias Octomocto.{Accounts, Friends, OnlineUsers, Players}
  alias OctomoctoWeb.{HomeLive, NotFoundError}

  def mount(%{"public_id" => id}, _session, socket) do
    user = Players.user(id) || raise NotFoundError

    # A user with a handle has the lists at the handle
    if user.handle && id != user.handle,
      do: {:ok, push_navigate(socket, to: list_path(user.handle, socket.assigns.live_action))},
      else: mount_lists(user, socket)
  end

  defp list_path(id, :followers), do: ~p"/players/#{id}/followers"
  defp list_path(id, :following), do: ~p"/players/#{id}/following"

  defp mount_lists(user, socket) do
    name = Accounts.public_name(user) || "Guest"

    if connected?(socket) and socket.assigns.current_scope, do: OnlineUsers.subscribe()

    {:ok,
     assign(socket,
       noindex: true,
       user_id: user.id,
       name: name,
       public_id: user.handle || user.public_id,
       viewer_id: viewer_id(socket)
     )}
  end

  def handle_params(_params, _url, socket) do
    list = socket.assigns.live_action
    title = if list == :followers, do: "Followers of", else: "Followed by"

    players =
      list
      |> then(&apply(Friends, &1, [socket.assigns.user_id]))
      |> Enum.map(
        &%{
          id: &1.id,
          name: Accounts.public_name(&1),
          avatar_url: &1.avatar_url,
          public_id: &1.public_id,
          handle: &1.handle
        }
      )
      |> Enum.sort_by(&String.downcase(&1.name || ""))

    {:noreply,
     socket
     |> assign(page_title: "#{title} #{socket.assigns.name}", list: list, players: players)
     |> assign_viewer()}
  end

  def handle_event("follow", %{"id" => id}, socket) do
    with {:ok, id} <- row_id(socket, id), do: Friends.follow(socket.assigns.viewer_id, id)
    {:noreply, assign_viewer(socket)}
  end

  def handle_event("unfollow", %{"id" => id}, socket) do
    with {:ok, id} <- row_id(socket, id), do: Friends.unfollow(socket.assigns.viewer_id, id)
    {:noreply, assign_viewer(socket)}
  end

  # A user came, left or changed the page
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_activities(socket)}
  end

  # Only a player in the list, and only for a signed-in viewer
  defp row_id(%{assigns: %{viewer_id: nil}}, _id), do: :error

  defp row_id(socket, id) do
    case Integer.parse(id) do
      {id, ""} ->
        if Enum.any?(socket.assigns.players, &(&1.id == id)), do: {:ok, id}, else: :error

      _ ->
        :error
    end
  end

  # The counts on the tabs, and who the viewer follows and is followed by
  defp assign_viewer(%{assigns: assigns} = socket) do
    {following, followers} =
      if assigns.viewer_id,
        do:
          {MapSet.new(Friends.followed_ids(assigns.viewer_id)),
           MapSet.new(Friends.follower_ids(assigns.viewer_id))},
        else: {MapSet.new(), MapSet.new()}

    socket
    |> assign(
      counts: Friends.counts(assigns.user_id),
      viewer_following: following,
      viewer_followers: followers,
      # The players in the list that the viewer can see online
      shared_ids:
        for(
          player <- assigns.players,
          player.id in following and player.id in followers,
          into: MapSet.new(),
          do: player.id
        )
    )
    |> assign_activities()
  end

  defp assign_activities(%{assigns: %{shared_ids: shared_ids}} = socket) do
    activities =
      if MapSet.size(shared_ids) > 0,
        do: OnlineUsers.activities(MapSet.to_list(shared_ids)),
        else: %{}

    assign(socket, activities: activities)
  end

  defp viewer_id(socket) do
    case socket.assigns.current_scope do
      %{user: %{id: id}} -> id
      _ -> nil
    end
  end
end
