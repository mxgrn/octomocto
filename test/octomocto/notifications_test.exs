defmodule Octomocto.NotificationsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.NotificationsFixtures

  alias Octomocto.Notifications

  describe "active_notifications/1" do
    test "gives the site-wide and the game notifications in the order they were added" do
      first = notification_fixture(game: "memory")
      second = notification_fixture()
      notification_fixture(game: "trains")

      assert Enum.map(Notifications.active_notifications("memory"), & &1.id) ==
               [first.id, second.id]
    end

    test "gives only the site-wide notifications for a page without a game" do
      site_wide = notification_fixture()
      notification_fixture(game: "memory")

      assert Enum.map(Notifications.active_notifications(nil), & &1.id) == [site_wide.id]
    end

    test "does not give expired notifications" do
      notification_fixture(expires_at: DateTime.add(DateTime.utc_now(), -1, :second))

      assert Notifications.active_notifications(nil) == []
    end
  end

  describe "create_notification/1" do
    test "requires the text and the expiration" do
      assert {:error, changeset} = Notifications.create_notification(%{})
      assert %{text: ["can't be blank"], expires_at: ["can't be blank"]} = errors_on(changeset)
    end

    test "does not accept text on more than one line" do
      assert {:error, changeset} =
               Notifications.create_notification(%{
                 text: "One\ntwo",
                 expires_at: DateTime.utc_now()
               })

      assert %{text: ["must be on one line"]} = errors_on(changeset)
    end

    test "does not accept an unknown game" do
      assert {:error, changeset} =
               Notifications.create_notification(%{
                 text: "Hello",
                 game: "chess",
                 expires_at: DateTime.utc_now()
               })

      assert %{game: ["is invalid"]} = errors_on(changeset)
    end
  end
end
