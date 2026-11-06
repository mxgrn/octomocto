defmodule Octomocto.MemoryTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.Accounts.Scope
  alias Octomocto.Memory

  defp save(theme, player) do
    player =
      Map.merge(
        %{user_id: nil, guest_id: nil, name: "Ann", score: 8, correct: nil, errors: nil},
        player
      )

    Memory.save_results("game", %{"cards" => 16}, theme, 1000, [player])
  end

  test "theme_counts/2 counts the results of the user for each theme" do
    user = user_fixture()
    save("cats", %{user_id: user.id})
    save("cats", %{user_id: user.id})
    save("space", %{user_id: user.id})
    save("cats", %{user_id: user_fixture().id})

    assert Memory.theme_counts(Scope.for_user(user), nil) == %{"cats" => 2, "space" => 1}
  end

  test "theme_counts/2 counts the results of a guest" do
    guest_id = Ecto.UUID.generate()
    save("space", %{guest_id: guest_id})

    assert Memory.theme_counts(nil, guest_id) == %{"space" => 1}
  end
end
