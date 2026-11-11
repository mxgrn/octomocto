defmodule Octomocto.NotificationsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  import Ecto.Query

  alias Octomocto.{Friends, Notifications, Repo}
  alias Octomocto.Notifications.Broadcast

  setup do
    %{follower: user_fixture().id, user: user_fixture().id}
  end

  test "a follow notifies the followed user", %{follower: follower, user: user} do
    Notifications.subscribe(user)

    Friends.follow(follower, user)

    assert_receive {:unread_notifications, 1}
    assert [%{kind: :followed, actor_id: ^follower}] = Notifications.list(user)
  end

  test "mark_seen/1 makes all notifications read", %{follower: follower, user: user} do
    Friends.follow(follower, user)

    Notifications.mark_seen(user)

    assert Notifications.unread_count(user) == 0
  end

  test "an unfollow removes an unread notification", %{follower: follower, user: user} do
    Friends.follow(follower, user)

    Friends.unfollow(follower, user)

    assert Notifications.unread_count(user) == 0
    Friends.follow(follower, user)
    assert Notifications.unread_count(user) == 1
  end

  test "a second follow after a read one does not notify again",
       %{follower: follower, user: user} do
    Friends.follow(follower, user)
    Notifications.mark_seen(user)
    Friends.unfollow(follower, user)

    assert Notifications.list(user) == []
    Friends.follow(follower, user)

    assert Notifications.unread_count(user) == 0
    assert [_read] = Notifications.list(user)
  end

  test "the friends from a shared game link get no notifications",
       %{follower: creator, user: user} do
    Friends.maybe_record(%{
      creator: "a",
      players: %{"a" => %{user_id: creator}, "b" => %{user_id: user}}
    })

    assert Notifications.unread_count(user) == 0
    assert Notifications.unread_count(creator) == 0
  end

  describe "a lost first place" do
    @back2 %{"back" => 2, "players" => 1}

    test "a new #1 of the Best results notifies the old #1", %{follower: rival, user: user} do
      snap(user, 10)
      Notifications.subscribe(user)

      snap(rival, 20)

      assert_receive {:unread_notifications, 1}

      assert [%{kind: :lost_top, actor_id: ^rival, game: "snap", settings: @back2}] =
               Notifications.list(user)
    end

    test "a better result of the #1 notifies nobody", %{user: user} do
      snap(user, 10)

      snap(user, 20)

      assert Notifications.list(user) == []
    end

    test "a result below #1 notifies nobody", %{follower: rival, user: user} do
      snap(user, 20)

      snap(rival, 10)

      assert Notifications.list(user) == []
    end

    test "each new push notifies again", %{follower: rival, user: user} do
      snap(user, 10)
      snap(rival, 20)
      snap(user, 30)

      snap(rival, 40)

      assert [_, _] = Notifications.list(user)
    end

    test "a campaign run notifies nobody", %{follower: rival, user: user} do
      settings = %{
        "switch_count" => 6,
        "trains_per_house" => 2,
        "pace" => "normal",
        "players" => 1,
        "campaign" => 1
      }

      Octomocto.Trains.save_results("a", settings, 5, [%{user_id: user}])

      Octomocto.Trains.save_results("b", settings, 9, [%{user_id: rival}])

      assert Notifications.list(user) == []
    end

    defp snap(user_id, score) do
      Octomocto.Snap.save_results("game", %{"back" => 2, "players" => 1}, 0, [
        %{user_id: user_id, score: score, correct: score, wrong: 0}
      ])
    end
  end

  describe "broadcasts" do
    test "a broadcast notifies the users who signed up before it", %{user: user} do
      Notifications.subscribe_broadcasts()

      {:ok, broadcast} = Notifications.create_broadcast(%{text: "New game"})

      assert_receive :broadcast_added
      assert Notifications.unread_count(user) == 1
      assert [%Broadcast{id: id}] = Notifications.list(user)
      assert id == broadcast.id
    end

    test "a user does not get the broadcasts from before the signup" do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "Old news"})
      backdate(broadcast)

      user = user_fixture().id

      assert Notifications.unread_count(user) == 0
      assert Notifications.list(user) == []
    end

    test "mark_seen/1 also makes the broadcasts read", %{user: user} do
      Notifications.create_broadcast(%{text: "New game"})

      Notifications.mark_seen(user)

      assert Notifications.unread_count(user) == 0
    end

    test "a guest gets the broadcasts after the given time" do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "New game"})
      before = DateTime.add(broadcast.inserted_at, -1, :second)

      assert Notifications.guest_unread_count(before) == 1
      assert Notifications.guest_unread_count(broadcast.inserted_at) == 0
      assert [%Broadcast{}] = Notifications.guest_list(before)
      assert Notifications.guest_list(broadcast.inserted_at) == []
    end

    test "a test broadcast goes only to the admins", %{user: user} do
      admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

      {:ok, broadcast} = Notifications.send_test_broadcast(%Broadcast{}, %{text: "New game"})
      before = DateTime.add(broadcast.inserted_at, -1, :second)

      assert Notifications.unread_count(admin.id) == 1
      assert Notifications.unread_count(user) == 0
      assert Notifications.guest_unread_count(before) == 0
      assert Notifications.guest_list(before) == []
    end

    test "a test broadcast sent to all gets the new text and time", %{user: user} do
      {:ok, test} = Notifications.send_test_broadcast(%Broadcast{}, %{text: "Typo"})
      backdate(test)
      test = Repo.reload!(test)

      {:ok, broadcast} = Notifications.send_broadcast(test, %{text: "Fixed"})

      assert broadcast.id == test.id
      assert broadcast.status == :sent
      assert DateTime.after?(broadcast.inserted_at, test.inserted_at)
      assert [%Broadcast{text: "Fixed"}] = Notifications.list(user)
    end

    test "a broadcast to the users does not go to the guests", %{user: user} do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hi", audience: :users})
      before = DateTime.add(broadcast.inserted_at, -1, :second)

      assert Notifications.unread_count(user) == 1
      assert Notifications.guest_unread_count(before) == 0
    end

    test "a broadcast to the guests does not go to the users", %{user: user} do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hi", audience: :guests})
      before = DateTime.add(broadcast.inserted_at, -1, :second)

      assert Notifications.unread_count(user) == 0
      assert Notifications.guest_unread_count(before) == 1
    end

    test "a test to the guests goes to the admins" do
      admin = user_fixture() |> Ecto.Changeset.change(role: :admin) |> Repo.update!()

      Notifications.send_test_broadcast(%Broadcast{}, %{text: "Hi", audience: :guests})

      assert Notifications.unread_count(admin.id) == 1
    end

    test "a change of a sent broadcast keeps the audience" do
      {:ok, broadcast} = Notifications.create_broadcast(%{text: "Hi", audience: :users})

      {:ok, broadcast} =
        Notifications.update_broadcast(broadcast, %{text: "Hello", audience: :guests})

      assert %{text: "Hello", audience: :users} = broadcast
    end

    test "a broadcast can have more than one line" do
      assert {:ok, %{text: "a\nb"}} = Notifications.create_broadcast(%{text: "a\nb"})
    end
  end

  defp backdate(broadcast) do
    Repo.update_all(from(b in Broadcast, where: b.id == ^broadcast.id),
      set: [inserted_at: DateTime.add(DateTime.utc_now(), -1, :day)]
    )
  end
end
