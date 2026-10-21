defmodule Octomocto.Notifications do
  @moduledoc """
  The notifications that admins write on the /admin pages. A notification
  is for all pages, or only for the pages of one game.

  A page shows one notification at a time: the first that the user did not
  close, in the order the notifications were added. The browser keeps the
  closed notifications (see `OctomoctoWeb.SiteNotifications`).
  """
  import Ecto.Query

  alias Octomocto.Notifications.Notification
  alias Octomocto.Repo

  @doc "Gives all notifications, also the expired ones, in the order they were added."
  def list_notifications do
    Repo.all(from n in Notification, order_by: n.id)
  end

  @doc """
  Gives the notifications that did not expire for the pages of the `game`
  (an id in `OctomoctoWeb.HomeLive.games/0`), in the order they were added.
  The site-wide notifications are included. A nil `game` gives only the
  site-wide notifications.
  """
  def active_notifications(game) do
    now = DateTime.utc_now()

    query =
      from n in Notification,
        where: n.expires_at > ^now,
        order_by: n.id

    query =
      if game,
        do: where(query, [n], is_nil(n.game) or n.game == ^game),
        else: where(query, [n], is_nil(n.game))

    Repo.all(query)
  end

  def get_notification!(id), do: Repo.get!(Notification, id)

  def create_notification(attrs) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end

  def update_notification(%Notification{} = notification, attrs) do
    notification
    |> Notification.changeset(attrs)
    |> Repo.update()
  end

  def delete_notification(%Notification{} = notification), do: Repo.delete(notification)

  def change_notification(%Notification{} = notification, attrs \\ %{}) do
    Notification.changeset(notification, attrs)
  end
end
