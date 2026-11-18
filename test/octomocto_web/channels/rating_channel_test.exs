defmodule OctomoctoWeb.RatingChannelTest do
  use OctomoctoWeb.ChannelCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.{Ratings, Repo, Trains}
  alias OctomoctoWeb.{RatingChannel, UserSocket}

  defp play_trains(user, games) do
    now = DateTime.utc_now()

    rows =
      for n <- 1..games do
        %{game_id: "game-#{n}", settings: %{}, score: 0, user_id: user.id, inserted_at: now}
      end

    Repo.insert_all(Trains.Result, rows)
  end

  defp join_rating(user_id, lang \\ "en") do
    UserSocket
    |> socket(nil, %{user_id: user_id})
    |> subscribe_and_join(RatingChannel, "rating:trains", %{"locale" => lang})
  end

  test "the texts are in the language of the page" do
    {:ok, %{texts: %{title: title}}, _socket} = join_rating(nil, "pt-BR")

    assert title == "Você está curtindo este jogo?"
  end

  test "a player with 5 games votes and comments" do
    user = user_fixture()
    play_trains(user, 5)

    {:ok, %{show: true}, socket} = join_rating(user.id)

    assert_reply push(socket, "vote", %{"stars" => 2}), :ok
    assert_reply push(socket, "comment", %{"text" => "Too slow"}), :ok
    refute Ratings.show?(user.id, "trains")
  end

  test "a guest does not see the card and cannot vote" do
    {:ok, %{show: false}, socket} = join_rating(nil)

    assert_reply push(socket, "vote", %{"stars" => 5}), :error
  end
end
