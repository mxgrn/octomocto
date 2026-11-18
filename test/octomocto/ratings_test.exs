defmodule Octomocto.RatingsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.{Memory, Ratings, Repo}

  defp play_memory(user, games) do
    now = DateTime.utc_now()

    rows =
      for n <- 1..games//1 do
        %{
          game_id: "game-#{n}",
          settings: %{},
          score: 0,
          elapsed_ms: 0,
          user_id: user.id,
          inserted_at: now
        }
      end

    Repo.insert_all(Memory.Result, rows)
  end

  describe "show?/2" do
    test "is true from the 5th game of the game until the vote" do
      user = user_fixture()
      play_memory(user, 4)
      refute Ratings.show?(user.id, "memory")

      play_memory(user, 1)
      assert Ratings.show?(user.id, "memory")

      {:ok, _} = Ratings.vote(user.id, "memory", 4)
      refute Ratings.show?(user.id, "memory")
    end

    test "counts only the games of that game" do
      user = user_fixture()
      play_memory(user, 5)

      refute Ratings.show?(user.id, "trains")
    end

    test "is false for a guest" do
      refute Ratings.show?(nil, "memory")
    end
  end

  describe "vote/3" do
    test "saves one vote for each user and game" do
      user = user_fixture()
      play_memory(user, 5)

      assert {:ok, %{stars: 3}} = Ratings.vote(user.id, "memory", 3)
      assert {:error, :not_allowed} = Ratings.vote(user.id, "memory", 5)
    end

    test "refuses a vote before 5 games" do
      user = user_fixture()
      play_memory(user, 4)

      assert {:error, :not_allowed} = Ratings.vote(user.id, "memory", 3)
    end

    test "refuses stars out of 1 to 5" do
      user = user_fixture()
      play_memory(user, 5)

      assert {:error, %Ecto.Changeset{}} = Ratings.vote(user.id, "memory", 6)
    end
  end

  describe "comment/3" do
    test "adds the comment to a vote of 1 to 4 stars" do
      user = user_fixture()
      play_memory(user, 5)
      {:ok, _} = Ratings.vote(user.id, "memory", 2)

      assert {:ok, %{comment: "Too hard"}} = Ratings.comment(user.id, "memory", "  Too hard ")
    end

    test "refuses a comment on a vote of 5 stars" do
      user = user_fixture()
      play_memory(user, 5)
      {:ok, _} = Ratings.vote(user.id, "memory", 5)

      assert {:error, :not_allowed} = Ratings.comment(user.id, "memory", "Great")
    end
  end
end
