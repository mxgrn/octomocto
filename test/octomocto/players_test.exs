defmodule Octomocto.PlayersTest do
  use Octomocto.DataCase, async: true

  import Ecto.Query
  import Octomocto.AccountsFixtures

  alias Octomocto.Friends.Follow
  alias Octomocto.Guests.Guest
  alias Octomocto.{Players, NimbleMosaic, Snap}

  @settings %{"type" => "random", "mode" => "easy", "players" => 1}

  test "profile/1 gives the games of a user in each game and the friends" do
    user = user_fixture()
    friend = user_fixture()
    now = DateTime.utc_now(:second)

    Repo.insert_all(Follow, [
      %{follower_id: user.id, followed_id: friend.id, inserted_at: now},
      %{follower_id: friend.id, followed_id: user.id, inserted_at: now}
    ])

    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    NimbleMosaic.save_results("b", @settings, 1000, [%{user_id: user.id, score: 90}])
    Snap.save_results("c", %{}, 0, [%{user_id: user.id, score: 5, correct: 5, wrong: 0}])

    assert %{guest: false, games: %{"nimble-mosaic" => 2, "snap" => 1}, friends: 1} =
             Players.profile(user.public_id)
  end

  test "profile/1 gives the games per day of the last 30 days in each game" do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    NimbleMosaic.save_results("b", @settings, 1000, [%{user_id: user.id, score: 90}])

    assert %{activity: %{"nimble-mosaic" => days} = activity} = Players.profile(user.public_id)
    assert map_size(activity) == 1
    assert length(days) == 30
    assert List.last(days) == 2
    assert Enum.sum(days) == 2
  end

  test "profile/1 gives a guest with no friends count" do
    guest_id = Ecto.UUID.generate()

    NimbleMosaic.save_results("a", @settings, 1000, [
      %{user_id: nil, guest_id: guest_id, name: "Brave Otter", score: 90}
    ])

    guest = Repo.get!(Guest, guest_id)

    assert %{name: "Brave Otter", guest: true, games: %{"nimble-mosaic" => 1}, friends: nil} =
             Players.profile(guest.public_id)
  end

  test "profile/1 gives the time of the last finished game in all games" do
    user = user_fixture()
    NimbleMosaic.save_results("a", @settings, 1000, [%{user_id: user.id, score: 90}])
    Snap.save_results("b", %{}, 0, [%{user_id: user.id, score: 5, correct: 5, wrong: 0}])

    last = Repo.one!(from r in Snap.Result, select: r.inserted_at)

    assert %{last_played_at: ^last} = Players.profile(user.public_id)
  end

  test "profile/1 gives no last game time for a user with no games" do
    assert %{last_played_at: nil} = Players.profile(user_fixture().public_id)
  end

  test "profile/1 gives nil for an unknown public id" do
    assert Players.profile("unknown1") == nil
  end

  test "a guest seat gets the public id after the first finished field" do
    guest_id = Ecto.UUID.generate()

    {player_id, state} =
      Octomocto.Seats.new("game", %{players: 1, public: false})
      |> Octomocto.Seats.add(self(), nil, "Brave Otter", guest_id, false, %{score: 90})

    assert state.players[player_id].public_id == nil

    NimbleMosaic.save_results("a", @settings, 1000, Map.values(state.players))
    state = Octomocto.Seats.refresh_public_ids(state)

    assert state.players[player_id].public_id == Repo.get!(Guest, guest_id).public_id
  end

  test "public_id/2 gives nil for a guest without a row" do
    assert Players.public_id(nil, Ecto.UUID.generate()) == nil
  end
end
