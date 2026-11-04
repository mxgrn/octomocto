defmodule OctomoctoWeb.InviteChannel do
  @moduledoc """
  The invites of the menu of a game page (`octo-game-menu` in
  `game_menu.js`). The topic is `"invites:<kind>:<game id>"`, with the
  kind of the game (an id in `OctomoctoWeb.HomeLive.games/0`), and the
  `"locale"` of the page in the join params.

  The join reply, and each `"update"` push after a change, has:

    * `:can_invite` - true for a signed-in player of a game that waits for
      players,
    * `:multiplayer` - true for a game for more than one player (the menu
      shows no invites for a single-player game),
    * `:guest` - true when the browser has no signed-in user,
    * `:friends` - the friends of the user who are online and not in the
      game, each with `:invited` when the user invited them from this page,
    * `:texts` - the texts of the menu in the locale of the page.

  The `"invite"` event with a `"friend_id"` sends a notice to the friend
  (see `Octomocto.Notices`), with a button that opens the game. A friend
  gets one invite from each page.
  """
  use Phoenix.Channel

  alias Octomocto.{Accounts, Friends, Notices, OnlineUsers}
  alias OctomoctoWeb.HomeLive

  # How long an invite stays in the bar of the friend
  @invite_ms :timer.minutes(2)

  @impl true
  def join("invites:" <> topic, params, socket) do
    with [kind, id] <- String.split(topic, ":", parts: 2),
         {game, store, _page} <- HomeLive.lobby_modules(kind) do
      if locale = params["locale"], do: Gettext.put_locale(OctomoctoWeb.Gettext, locale)
      user_id = socket.assigns.user_id
      friends = if user_id, do: Friends.friends(user_id), else: []

      if user_id do
        OnlineUsers.subscribe()
        Phoenix.PubSub.subscribe(Octomocto.PubSub, game.topic(id))
      end

      socket =
        assign(socket, kind: kind, id: id, store: store, friends: friends, invited: MapSet.new())

      reply = menu(socket)
      {:ok, reply, assign(socket, last: reply)}
    else
      _ -> {:error, %{reason: "not_found"}}
    end
  end

  @impl true
  def handle_in("invite", %{"friend_id" => friend_id}, socket) do
    menu = menu(socket)

    if menu.can_invite and Enum.any?(menu.friends, &(&1.id == friend_id)) do
      send_invite(socket, friend_id)
      invited = MapSet.put(socket.assigns.invited, friend_id)
      {:reply, :ok, socket |> assign(invited: invited) |> push_update()}
    else
      {:reply, :error, socket}
    end
  end

  # A user came or left, or the game changed
  @impl true
  def handle_info(_message, socket), do: {:noreply, push_update(socket)}

  defp push_update(socket) do
    menu = menu(socket)

    if menu == socket.assigns.last do
      socket
    else
      push(socket, "update", menu)
      assign(socket, last: menu)
    end
  end

  defp menu(%{assigns: assigns}) do
    state = assigns.store.read(assigns.id)

    in_game =
      if state, do: MapSet.new(Map.values(state.players), & &1.user_id), else: MapSet.new()

    online = OnlineUsers.activities(Enum.map(assigns.friends, & &1.id))

    friends =
      for friend <- assigns.friends,
          is_map_key(online, friend.id) and not MapSet.member?(in_game, friend.id) do
        %{
          id: friend.id,
          name: Accounts.public_name(friend),
          avatar_url: friend.avatar_url,
          invited: MapSet.member?(assigns.invited, friend.id)
        }
      end

    %{
      can_invite:
        state != nil and assigns.user_id != nil and MapSet.member?(in_game, assigns.user_id) and
          map_size(state.players) < state.needed,
      multiplayer: state != nil and state.needed > 1,
      guest: assigns.user_id == nil,
      friends: Enum.sort_by(friends, &String.downcase(&1.name || "")),
      texts: texts()
    }
  end

  defp send_invite(%{assigns: assigns}, friend_id) do
    name = Accounts.display_name(assigns.user_id)
    game = Enum.find(HomeLive.games(), &(&1.id == assigns.kind))

    Notices.push({:user, friend_id}, %{
      id: "invite:#{assigns.id}:#{assigns.user_id}",
      text: "#{name} invites you to #{game.name}",
      actions: [
        %{id: "join", label: "Join", href: "/#{assigns.kind}/#{assigns.id}"},
        %{id: "later", label: "Not now", href: nil}
      ],
      expires_at: System.system_time(:millisecond) + @invite_ms
    })
  end

  defp texts do
    %{
      invite_title: gettext("Invite a friend"),
      invite: gettext("Invite"),
      invited: gettext("Invited"),
      sign_in: gettext("Sign in to invite your friends."),
      no_friends: gettext("No friends online."),
      not_waiting: gettext("You can invite friends while the game waits for players.")
    }
  end

  defp gettext(text), do: Gettext.gettext(OctomoctoWeb.Gettext, text)
end
