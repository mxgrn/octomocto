defmodule OctomoctoWeb.InviteChannelTest do
  # Not async: the game process reads the public id of the user (see
  # `Octomocto.Seats.add/7`), so it needs the shared sandbox
  use OctomoctoWeb.ChannelCase, async: false

  import Octomocto.GameHelpers
  import Octomocto.AccountsFixtures

  alias Octomocto.Friends.Follow
  alias Octomocto.{Notices, OnlineUsers, Repo, Schulte}
  alias OctomoctoWeb.{InviteChannel, UserSocket}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    start_supervised!(schulte_game(id, players: 2))
    %{id: id}
  end

  defp make_friends(user, friend) do
    now = DateTime.utc_now(:second)

    Repo.insert_all(Follow, [
      %{follower_id: user.id, followed_id: friend.id, inserted_at: now},
      %{follower_id: friend.id, followed_id: user.id, inserted_at: now}
    ])
  end

  # A page of the friend: one process for each page
  defp online(user) do
    page = spawn_link(fn -> receive do: (:never -> :ok) end)
    OnlineUsers.track(page, user.id, %{kind: nil, doing: nil})
  end

  defp join_menu(user_id, id) do
    UserSocket
    |> socket(nil, %{user_id: user_id})
    |> subscribe_and_join(InviteChannel, "invites:schulte:" <> id, %{"locale" => "en"})
  end

  test "a player of a waiting game invites a friend who is online", %{id: id} do
    [user, friend] = for _ <- 1..2, do: user_fixture()
    make_friends(user, friend)
    online(friend)
    {:ok, _, _} = Schulte.join(id, user.id)
    Notices.subscribe({:user, friend.id})
    friend_id = friend.id

    {:ok, %{can_invite: true, friends: [%{id: ^friend_id, status: "invite"}]}, socket} =
      join_menu(user.id, id)

    ref = push(socket, "invite", %{"friend_id" => friend.id})

    assert_reply ref, :ok
    assert_push "update", %{friends: [%{id: ^friend_id, status: "invited"}]}
    path = "/schulte/#{id}"
    assert_receive {:notice, %{actions: [%{id: "join", href: ^path} | _]}}
  end

  test "the menu shows that the friend declined the invite", %{id: id} do
    [user, friend] = for _ <- 1..2, do: user_fixture()
    make_friends(user, friend)
    online(friend)
    {:ok, _, _} = Schulte.join(id, user.id)
    Notices.subscribe({:user, friend.id})
    {:ok, _, socket} = join_menu(user.id, id)
    push(socket, "invite", %{"friend_id" => friend.id})
    assert_receive {:notice, notice}

    Notices.answer(notice, "later", {:user, friend.id})

    friend_id = friend.id
    assert_push "update", %{friends: [%{id: ^friend_id, status: "declined"}]}
  end

  test "a player cannot invite to a full game", %{id: id} do
    [user, friend] = for _ <- 1..2, do: user_fixture()
    make_friends(user, friend)
    online(friend)
    {:ok, _, _} = Schulte.join(id, user.id)
    {:ok, _, _} = Schulte.join(id)

    {:ok, %{can_invite: false}, socket} = join_menu(user.id, id)

    ref = push(socket, "invite", %{"friend_id" => friend.id})
    assert_reply ref, :error
  end

  test "a guest cannot invite", %{id: id} do
    assert {:ok, %{guest: true, can_invite: false, friends: []}, _socket} = join_menu(nil, id)
  end
end
