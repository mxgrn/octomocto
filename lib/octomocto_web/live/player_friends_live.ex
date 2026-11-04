defmodule OctomoctoWeb.PlayerFriendsLive do
  @moduledoc """
  The friends of a user, at `/players/:public_id/friends`. Anyone can open
  it. A row shows the online state and the activity only when that friend
  is also a friend of the viewer: presence is for friends only (see
  `Octomocto.OnlineUsers`). A guest has no friends, thus no such page.
  """
  use OctomoctoWeb, :live_view

  on_mount {OctomoctoWeb.SiteNotifications, nil}

  alias Octomocto.{Accounts, Friends, OnlineUsers, Players}
  alias OctomoctoWeb.{HomeLive, NotFoundError}

  def mount(%{"public_id" => public_id}, _session, socket) do
    user = Players.user(public_id) || raise NotFoundError

    friends =
      user.id
      |> Friends.friends()
      |> Enum.map(
        &%{
          id: &1.id,
          name: Accounts.public_name(&1),
          avatar_url: &1.avatar_url,
          public_id: &1.public_id
        }
      )
      |> Enum.sort_by(&String.downcase(&1.name || ""))

    # The friends in the list that the viewer can see online
    shared_ids =
      case socket.assigns.current_scope do
        %{user: viewer} ->
          viewer_ids = MapSet.new(Friends.friends(viewer.id), & &1.id)
          for friend <- friends, friend.id in viewer_ids, into: MapSet.new(), do: friend.id

        nil ->
          MapSet.new()
      end

    if connected?(socket) and MapSet.size(shared_ids) > 0, do: OnlineUsers.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "Friends of #{Accounts.public_name(user) || "Guest"}",
       noindex: true,
       name: Accounts.public_name(user) || "Guest",
       public_id: public_id,
       friends: friends,
       shared_ids: shared_ids
     )
     |> assign_activities()}
  end

  # A user came, left or changed the page
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_activities(socket)}
  end

  defp assign_activities(%{assigns: %{shared_ids: shared_ids}} = socket) do
    activities =
      if MapSet.size(shared_ids) > 0,
        do: OnlineUsers.activities(MapSet.to_list(shared_ids)),
        else: %{}

    assign(socket, activities: activities)
  end
end
