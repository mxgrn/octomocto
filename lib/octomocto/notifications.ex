defmodule Octomocto.Notifications do
  @moduledoc """
  The notifications of users and guests, at `/notifications` (see
  `OctomoctoWeb.NotificationsLive`). A dot on the menu in the header
  shows that there are unread ones (see `OctomoctoWeb.UnreadNotifications`).

  There are two types:

    * `Octomocto.Notifications.Notification`, to one user, of these kinds:
      * `:followed`: a user clicked Follow on the profile (see
        `Octomocto.Friends.follow/2`). The follows from a shared game link
        make no notification. There is one notification for each
        follower: a second follow from the same user does not notify
        again.
      * `:lost_top`: a user took the first place of the user in the Best
        results of a game (see `watch_top/5`). Each lost first place is a
        new notification.
    * `Octomocto.Notifications.Broadcast`, from the admins to all users
      and guests (at `/admin/notifications`). A user gets the broadcasts
      from after the signup. A guest gets the broadcasts from after the
      first visit. The `audience` can limit a broadcast to the users or to
      the guests. A broadcast with the status `:test` goes only to the
      admins, until an admin sends it.

  For a user, the notifications after `users.notifications_seen_at` are
  unread. A guest keeps the time of the first visit and the time when the
  guest saw the page in the session (see
  `OctomoctoWeb.UnreadNotifications`). When the user or the guest opens
  the page, all are read.
  """
  import Ecto.Query

  alias Octomocto.Accounts.User
  alias Octomocto.Friends.Follow
  alias Octomocto.Notifications.{Broadcast, Notification}
  alias Octomocto.Repo

  @doc "The number of notifications that show on the page."
  def limit, do: 50

  def topic(user_id), do: "notifications:user:#{user_id}"

  @doc """
  The pages of the user get `{:unread_notifications, count}` when the
  count changes.
  """
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, topic(user_id))

  @broadcasts_topic "notifications:broadcasts"

  @doc """
  The pages of all users and guests get `:broadcast_added` when an admin
  adds a broadcast.
  """
  def subscribe_broadcasts, do: Phoenix.PubSub.subscribe(Octomocto.PubSub, @broadcasts_topic)

  @doc "Notifies the user `followed_id` that the user `follower_id` follows them."
  def followed(follower_id, followed_id) do
    {count, _} =
      Repo.insert_all(
        Notification,
        [
          %{
            user_id: followed_id,
            kind: :followed,
            actor_id: follower_id,
            inserted_at: DateTime.utc_now()
          }
        ],
        on_conflict: :nothing
      )

    if count > 0, do: broadcast_count(followed_id)
    :ok
  end

  @doc """
  Runs `save`, the insert of the results of one field of the `game`, and
  notifies the user who was first in the Best results of the `settings`
  (all players) before the insert, when another user is first after it.
  The `context` gives the Best results (`best_results/1`). A campaign run
  is not in the Best results, and a field with no signed-in players
  cannot change the first place, so they skip the check. Gives the value
  of `save`.
  """
  def watch_top(context, game, settings, players, save) do
    if Map.has_key?(settings, "campaign") or not Enum.any?(players, &Map.get(&1, :user_id)) do
      save.()
    else
      before = top_user_id(context, settings)
      result = save.()
      now = top_user_id(context, settings)
      if before && now != before, do: lost_top(before, now, game, settings)
      result
    end
  end

  defp top_user_id(context, settings) do
    case context.best_results(settings) do
      [first | _] -> first.user_id
      [] -> nil
    end
  end

  @doc """
  Notifies the user `user_id` that the user `actor_id` took the first
  place in the Best results of the `game` with the `settings`.
  """
  def lost_top(user_id, actor_id, game, settings) do
    Repo.insert_all(Notification, [
      %{
        user_id: user_id,
        kind: :lost_top,
        actor_id: actor_id,
        game: game,
        settings: settings,
        inserted_at: DateTime.utc_now()
      }
    ])

    broadcast_count(user_id)
    :ok
  end

  @doc """
  Removes the notification of the follow, when the user `followed_id` did
  not read it yet. A read one stays, so that a new follow does not notify
  again.
  """
  def unfollowed(follower_id, followed_id) do
    {count, _} =
      Repo.delete_all(
        from n in unread(followed_id),
          where: n.kind == :followed and n.actor_id == ^follower_id
      )

    if count > 0, do: broadcast_count(followed_id)
    :ok
  end

  @doc "The number of unread notifications of the user, with the broadcasts."
  def unread_count(user_id) do
    Repo.aggregate(unread(user_id), :count) +
      Repo.aggregate(unread_broadcasts(user_id), :count)
  end

  defp unread(user_id) do
    from n in Notification,
      join: u in User,
      on: u.id == n.user_id,
      where: n.user_id == ^user_id,
      where: is_nil(u.notifications_seen_at) or n.inserted_at > u.notifications_seen_at
  end

  # The broadcasts after the signup and after the last visit of the page
  defp unread_broadcasts(user_id) do
    from [b, user: u] in user_broadcasts(user_id),
      where: is_nil(u.notifications_seen_at) or b.inserted_at > u.notifications_seen_at
  end

  defp user_broadcasts(user_id) do
    from b in Broadcast,
      join: u in User,
      as: :user,
      on: u.id == ^user_id,
      where: b.inserted_at > u.inserted_at,
      where:
        (b.status == :sent and b.audience in [:all, :users]) or
          (b.status == :test and u.role == :admin)
  end

  @doc """
  The newest notifications of the user, with the actor, and the
  broadcasts from after the signup. A follow notification shows only
  while the follow exists.
  """
  def list(user_id) do
    newest =
      from n in Notification,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at, desc: n.id],
        limit: ^limit(),
        preload: :actor

    follows =
      Repo.all(
        from n in newest,
          join: f in Follow,
          on: f.follower_id == n.actor_id and f.followed_id == n.user_id,
          where: n.kind == :followed
      )

    lost_tops = Repo.all(from n in newest, where: n.kind == :lost_top)

    broadcasts =
      Repo.all(
        from b in user_broadcasts(user_id), order_by: [desc: b.inserted_at], limit: ^limit()
      )

    (follows ++ lost_tops ++ broadcasts)
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.take(limit())
  end

  @doc "The number of broadcasts after `since`, for a guest."
  def guest_unread_count(%DateTime{} = since),
    do: Repo.aggregate(broadcasts_after(since), :count)

  @doc "The newest broadcasts after `since` (the first visit), for a guest."
  def guest_list(%DateTime{} = since) do
    Repo.all(from b in broadcasts_after(since), order_by: [desc: b.inserted_at], limit: ^limit())
  end

  defp broadcasts_after(since),
    do:
      from(b in Broadcast,
        where: b.status == :sent and b.audience in [:all, :guests] and b.inserted_at > ^since
      )

  @doc """
  Marks all notifications of the user as read. Gives the time when the
  user saw them before, or nil.
  """
  def mark_seen(user_id) do
    seen_at = Repo.one(from u in User, where: u.id == ^user_id, select: u.notifications_seen_at)

    Repo.update_all(from(u in User, where: u.id == ^user_id),
      set: [notifications_seen_at: DateTime.utc_now()]
    )

    broadcast_count(user_id, 0)
    seen_at
  end

  defp broadcast_count(user_id, count \\ nil) do
    Phoenix.PubSub.broadcast(
      Octomocto.PubSub,
      topic(user_id),
      {:unread_notifications, count || unread_count(user_id)}
    )
  end

  @doc "Gives all broadcasts, the newest first."
  def list_broadcasts, do: Repo.all(from b in Broadcast, order_by: [desc: b.inserted_at])

  def get_broadcast!(id), do: Repo.get!(Broadcast, id)

  @doc "Adds a broadcast and sends it to its audience."
  def create_broadcast(attrs), do: send_broadcast(%Broadcast{}, attrs)

  @doc """
  Sends the broadcast to its audience. A new one is added. A test
  one (see `send_test_broadcast/2`) gets the new text, the new audience
  and the time of now.
  """
  def send_broadcast(%Broadcast{} = broadcast, attrs), do: deliver(broadcast, attrs, :sent)

  @doc """
  Sends the broadcast only to the admins, so that they can see it before
  it goes to all. A test broadcast that is sent again gets the new text
  and the time of now.
  """
  def send_test_broadcast(%Broadcast{} = broadcast, attrs), do: deliver(broadcast, attrs, :test)

  # The open pages of all users and guests get the new count
  defp deliver(broadcast, attrs, status) do
    changeset = broadcast |> Broadcast.changeset(attrs) |> Ecto.Changeset.change(status: status)

    changeset =
      if broadcast.id,
        do: Ecto.Changeset.change(changeset, inserted_at: DateTime.utc_now()),
        else: changeset

    with {:ok, broadcast} <- Repo.insert_or_update(changeset) do
      Phoenix.PubSub.broadcast(Octomocto.PubSub, @broadcasts_topic, :broadcast_added)
      {:ok, broadcast}
    end
  end

  @doc """
  Changes the text of a sent broadcast. It does not make it unread again,
  and the audience stays.
  """
  def update_broadcast(%Broadcast{} = broadcast, attrs) do
    broadcast
    |> Broadcast.text_changeset(attrs)
    |> Repo.update()
  end

  def delete_broadcast(%Broadcast{} = broadcast), do: Repo.delete(broadcast)

  @doc """
  Translates the text of a broadcast into all languages other than
  English with the LLM (see `config :understudy`). Understudy translates in
  the background. Call it when an admin saves a broadcast, so that the
  translations are ready before the pages ask for them.
  """
  def translate(%Broadcast{text: text}) do
    if Application.get_env(:octomocto, :translate_broadcasts, true) do
      Task.Supervisor.start_child(Octomocto.TaskSupervisor, fn ->
        OctomoctoWeb.Locale.other_locales()
        |> Enum.each(&Understudy.translate(text, locale: &1, domain: "broadcasts"))
      end)
    end

    :ok
  end

  @doc """
  Gives the text of a broadcast in the language of the process. If the
  translation is not ready yet, or the LLM failed, it gives the English text.
  """
  def localized_text(%Broadcast{text: text}) do
    Understudy.translate(text,
      locale: Gettext.get_locale(OctomoctoWeb.Gettext),
      domain: "broadcasts"
    )
  end

  def change_broadcast(%Broadcast{} = broadcast, attrs \\ %{}),
    do: Broadcast.changeset(broadcast, attrs)
end
