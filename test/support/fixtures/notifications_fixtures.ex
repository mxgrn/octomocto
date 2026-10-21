defmodule Octomocto.NotificationsFixtures do
  @moduledoc """
  Test helpers for creating notifications in `Octomocto.Notifications`.
  """

  def notification_fixture(attrs \\ %{}) do
    {:ok, notification} =
      attrs
      |> Enum.into(%{text: "Hello", expires_at: DateTime.add(DateTime.utc_now(), 1, :day)})
      |> Octomocto.Notifications.create_notification()

    notification
  end
end
