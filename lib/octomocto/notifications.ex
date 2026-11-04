defmodule Octomocto.Notifications do
  @moduledoc """
  The notifications that admins write on the /admin pages. A notification
  is for all pages, or only for the pages of one game.

  A page shows one notification at a time: the first that the user did not
  close, in the order the notifications were added. The browser keeps the
  closed notifications (see `OctomoctoWeb.SiteNotifications`). The closes
  are also in the database (see `Octomocto.Notifications.Close`), for the
  statistics and so that a signed-in user does not see a closed
  notification again on other devices.
  """
  import Ecto.Query

  alias Octomocto.Accounts.Scope
  alias Octomocto.Guests
  alias Octomocto.Notifications.{Close, Notification}
  alias Octomocto.Repo

  @doc "Gives all notifications, also the expired ones, in the order they were added."
  def list_notifications do
    Repo.all(from n in Notification, order_by: n.id)
  end

  @doc """
  Gives the notifications that did not expire for the pages of the `game`
  (an id in `OctomoctoWeb.HomeLive.games/0`), in the order they were added.
  The site-wide notifications are included. A nil `game` gives only the
  site-wide notifications. For a signed-in user, the notifications that the
  user closed are omitted.
  """
  def active_notifications(game, scope \\ nil) do
    now = DateTime.utc_now()

    query =
      from n in Notification,
        where: n.expires_at > ^now,
        order_by: n.id

    query =
      if game,
        do: where(query, [n], is_nil(n.game) or n.game == ^game),
        else: where(query, [n], is_nil(n.game))

    scope
    |> omit_closed(query)
    |> Repo.all()
  end

  defp omit_closed(%Scope{user: %{id: user_id}}, query) do
    closed =
      from c in Close,
        where: c.notification_id == parent_as(:notification).id and c.user_id == ^user_id

    from n in query, as: :notification, where: not exists(closed)
  end

  defp omit_closed(_scope, query), do: query

  @doc """
  Saves that a user or a guest closed a notification. The `scope` gives
  the user. Without a user, the `guest` is `{id, name}` from the session,
  and the guest is saved first (see `Octomocto.Guests`). The first close is
  kept. A notification that does not exist is ignored.
  """
  def record_close(notification_id, scope, guest) do
    with %Notification{} <- Repo.get(Notification, notification_id),
         {field, id} <- closer(scope, guest) do
      Repo.insert_all(
        Close,
        [%{:notification_id => notification_id, field => id, :inserted_at => DateTime.utc_now()}],
        on_conflict: :nothing,
        conflict_target:
          {:unsafe_fragment, "(notification_id, #{field}) WHERE #{field} IS NOT NULL"}
      )
    end

    :ok
  end

  defp closer(%Scope{user: %{id: id}}, _guest), do: {:user_id, id}

  defp closer(_scope, {id, name}) when is_binary(id) and is_binary(name) do
    Guests.save([%{guest_id: id, name: name}], DateTime.utc_now())
    {:guest_id, id}
  end

  defp closer(_scope, _guest), do: nil

  @doc "Gives the number of closes of each notification, as a map from the notification id."
  def close_counts do
    from(c in Close, group_by: c.notification_id, select: {c.notification_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
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

  @doc """
  Translates the text of a notification into all languages other than
  English with the LLM (see `config :understudy`). Understudy translates in
  the background. Call it when an admin saves a notification, so that the
  translations are ready before the pages ask for them.
  """
  def translate(%Notification{text: text}) do
    if Application.get_env(:octomocto, :translate_notifications, true) do
      Task.Supervisor.start_child(Octomocto.TaskSupervisor, fn ->
        OctomoctoWeb.Locale.other_locales()
        |> Enum.each(&Understudy.translate(text, locale: &1, domain: "notifications"))
      end)
    end

    :ok
  end

  @doc """
  Gives the text of a notification in the language of the process. If the
  translation is not ready yet, or the LLM failed, it gives the English text.
  """
  def localized_text(%Notification{text: text}) do
    Understudy.translate(text,
      locale: Gettext.get_locale(OctomoctoWeb.Gettext),
      domain: "notifications"
    )
  end

  def change_notification(%Notification{} = notification, attrs \\ %{}) do
    Notification.changeset(notification, attrs)
  end
end
