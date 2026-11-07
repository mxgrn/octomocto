defmodule Octomocto.BannersTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures
  import Octomocto.BannersFixtures

  alias Octomocto.Guests.Guest
  alias Octomocto.Banners

  describe "active_banners/1" do
    test "gives the site-wide and the game banners in the order they were added" do
      first = banner_fixture(game: "memory")
      second = banner_fixture()
      banner_fixture(game: "trains")

      assert Enum.map(Banners.active_banners("memory"), & &1.id) ==
               [first.id, second.id]
    end

    test "gives only the site-wide banners for a page without a game" do
      site_wide = banner_fixture()
      banner_fixture(game: "memory")

      assert Enum.map(Banners.active_banners(nil), & &1.id) == [site_wide.id]
    end

    test "does not give expired banners" do
      banner_fixture(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))

      assert Banners.active_banners(nil) == []
    end
  end

  describe "active_banners/2" do
    test "omits the banners that the user closed" do
      closed = banner_fixture()
      open = banner_fixture()
      scope = user_scope_fixture()
      Banners.record_close(closed.id, scope, nil)

      assert Enum.map(Banners.active_banners(nil, scope), & &1.id) == [open.id]
    end

    test "gives the banners that other users closed" do
      banner = banner_fixture()
      Banners.record_close(banner.id, user_scope_fixture(), nil)

      assert Enum.map(Banners.active_banners(nil, user_scope_fixture()), & &1.id) ==
               [banner.id]
    end
  end

  describe "record_close/3" do
    test "saves one close for each user" do
      banner = banner_fixture()
      scope = user_scope_fixture()

      Banners.record_close(banner.id, scope, nil)
      Banners.record_close(banner.id, scope, nil)

      assert Banners.close_counts() == %{banner.id => 1}
    end

    test "saves the guest with the close" do
      banner = banner_fixture()
      guest_id = Ecto.UUID.generate()

      Banners.record_close(banner.id, nil, {guest_id, "Brave Otter"})

      assert %Guest{name: "Brave Otter"} = Repo.get(Guest, guest_id)
      assert Banners.close_counts() == %{banner.id => 1}
    end

    test "ignores a banner that does not exist" do
      Banners.record_close(-1, user_scope_fixture(), nil)

      assert Banners.close_counts() == %{}
    end
  end

  describe "create_banner/1" do
    test "requires the text and the expiration" do
      assert {:error, changeset} = Banners.create_banner(%{})
      assert %{text: ["can't be blank"], expires_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "does not accept text on more than one line" do
      assert {:error, changeset} =
               Banners.create_banner(%{
                 text: "One\ntwo",
                 expires_at: DateTime.utc_now()
               })

      assert %{text: ["must be on one line"]} = errors_on(changeset)
    end

    test "does not accept an unknown game" do
      assert {:error, changeset} =
               Banners.create_banner(%{
                 text: "Hello",
                 game: "chess",
                 expires_at: DateTime.utc_now()
               })

      assert %{game: ["is invalid"]} = errors_on(changeset)
    end
  end
end
