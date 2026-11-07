defmodule Octomocto.Notifications do
  @moduledoc """
  The notifications of each signed-in user, at `/notifications` (see
  `OctomoctoWeb.NotificationsLive`). A dot on the avatar in the header
  shows that there are unread ones (see `OctomoctoWeb.UnreadNotifications`).

  The notifications after `users.notifications_seen_at` are unread. When
  the user opens the page, all are read.

  The only kind now is `:followed`: a user clicked Follow on the profile
  (see `Octomocto.Friends.follow/2`). The follows from a shared game link
  make no notification. There is one notification for each follower: a
  second follow from the same user does not notify again.
  """
  import Ecto.Query

  alias Octomocto.Accounts.User
  alias Octomocto.Friends.Follow
  alias Octomocto.Notifications.Notification
  alias Octomocto.Repo

  @doc "The number of notifications that show on the page."
  def limit, do: 50

  def topic(user_id), do: "notifications:user:#{user_id}"

  @doc """
  The pages of the user get `{:unread_notifications, count}` when the
  count changes.
  """
  def subscribe(user_id), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, topic(user_id))

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

  @doc "The number of unread notifications of the user."
  def unread_count(user_id), do: Repo.aggregate(unread(user_id), :count)

  defp unread(user_id) do
    from n in Notification,
      join: u in User,
      on: u.id == n.user_id,
      where: n.user_id == ^user_id,
      where: is_nil(u.notifications_seen_at) or n.inserted_at > u.notifications_seen_at
  end

  @doc """
  The newest notifications of the user, with the actor. A follow
  notification shows only while the follow exists.
  """
  def list(user_id) do
    Repo.all(
      from n in Notification,
        join: f in Follow,
        on: f.follower_id == n.actor_id and f.followed_id == n.user_id,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at, desc: n.id],
        limit: ^limit(),
        preload: :actor
    )
  end

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
end
