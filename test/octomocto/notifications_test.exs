defmodule Octomocto.NotificationsTest do
  use Octomocto.DataCase, async: true

  import Octomocto.AccountsFixtures
  import Octomocto.NotificationsFixtures

  alias Octomocto.Guests.Guest
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

  describe "active_notifications/2" do
    test "omits the notifications that the user closed" do
      closed = notification_fixture()
      open = notification_fixture()
      scope = user_scope_fixture()
      Notifications.record_close(closed.id, scope, nil)

      assert Enum.map(Notifications.active_notifications(nil, scope), & &1.id) == [open.id]
    end

    test "gives the notifications that other users closed" do
      notification = notification_fixture()
      Notifications.record_close(notification.id, user_scope_fixture(), nil)

      assert Enum.map(Notifications.active_notifications(nil, user_scope_fixture()), & &1.id) ==
               [notification.id]
    end
  end

  describe "record_close/3" do
    test "saves one close for each user" do
      notification = notification_fixture()
      scope = user_scope_fixture()

      Notifications.record_close(notification.id, scope, nil)
      Notifications.record_close(notification.id, scope, nil)

      assert Notifications.close_counts() == %{notification.id => 1}
    end

    test "saves the guest with the close" do
      notification = notification_fixture()
      guest_id = Ecto.UUID.generate()

      Notifications.record_close(notification.id, nil, {guest_id, "Brave Otter"})

      assert %Guest{name: "Brave Otter"} = Repo.get(Guest, guest_id)
      assert Notifications.close_counts() == %{notification.id => 1}
    end

    test "ignores a notification that does not exist" do
      Notifications.record_close(-1, user_scope_fixture(), nil)

      assert Notifications.close_counts() == %{}
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
