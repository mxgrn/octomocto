defmodule Octomocto.Notifications do
  @moduledoc """
  The notifications that admins write on the /admin pages. A notification
  is for all pages, or only for the pages of one game.

  A page shows one notification at a time: the first that the user did not
  close, in the order the notifications were added. The browser keeps the
  closed notifications (see `OctomoctoWeb.SiteNotifications`).
  """
  import Ecto.Query

  alias Octomocto.LlmGettext
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

  @doc """
  Translates the text of a notification into all languages other than
  English with the LLM (see `Octomocto.LlmGettext`), in a background task.
  Call it when an admin saves a notification, so that no page waits for
  the LLM.
  """
  def translate(%Notification{text: text}) do
    if Application.get_env(:octomocto, :translate_notifications, true) do
      Task.Supervisor.start_child(Octomocto.TaskSupervisor, fn ->
        OctomoctoWeb.Locale.other_locales()
        |> Task.async_stream(&Understudy.translate(LlmGettext, text, locale: &1),
          timeout: :infinity
        )
        |> Stream.run()
      end)
    end

    :ok
  end

  @doc """
  Gives the text of a notification in the language of the process. If the
  translation is not in the cache, it waits for the LLM. If the LLM fails,
  it gives the English text.
  """
  def localized_text(%Notification{text: text}) do
    Understudy.translate(LlmGettext, text, locale: Gettext.get_locale(OctomoctoWeb.Gettext))
  end

  def change_notification(%Notification{} = notification, attrs \\ %{}) do
    Notification.changeset(notification, attrs)
  end
end
