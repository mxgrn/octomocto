defmodule OctomoctoWeb.BrowserLocaleTest do
  # The Schulte channel uses OctomoctoWeb.GameChannel, which writes the
  # browser locale when a game saves its results
  use OctomoctoWeb.ChannelCase, async: true

  import Octomocto.GameHelpers

  import Octomocto.AccountsFixtures

  alias Octomocto.Accounts.User
  alias Octomocto.Guests.Guest
  alias Octomocto.Repo
  alias OctomoctoWeb.{SchulteChannel, UserSocket}

  setup do
    id = "game-#{System.unique_integer([:positive])}"
    pid = start_supervised!(schulte_game(id))
    Ecto.Adapters.SQL.Sandbox.allow(Repo, self(), pid)
    %{id: id}
  end

  defp finish_game(id, assigns) do
    {:ok, _reply, socket} =
      UserSocket
      |> socket(nil, assigns)
      |> subscribe_and_join(SchulteChannel, "schulte:" <> id)

    for n <- 1..90, do: push(socket, "pick", %{"number" => n})

    # The game saves the results before it pushes the last state
    assert_push "state", %{next: 91}
  end

  test "a finished game saves the browser locale of a guest", %{id: id} do
    guest_id = Ecto.UUID.generate()

    finish_game(id, %{guest_id: guest_id, guest_name: "Brave Otter", browser_locale: "pt-BR"})

    assert Repo.get!(Guest, guest_id).locale == "pt-BR"
  end

  test "a finished game saves the browser locale of a user", %{id: id} do
    user = user_fixture()

    finish_game(id, %{user_id: user.id, browser_locale: "de-DE"})

    assert Repo.get!(User, user.id).locale == "de-DE"
  end
end
