defmodule Octomocto.OnlineUsers do
  @moduledoc """
  The signed-in users that have a page of the site open, in the whole
  cluster. Each LiveView page (see `OctomoctoWeb.OnlineUsers`) and each
  game channel (see `OctomoctoWeb.GameChannel`) of a user tracks its
  process with an activity:

    * `:kind` - the id of the game of the page (see
      `OctomoctoWeb.HomeLive.games/0`), or nil for another page,
    * `:doing` - `"playing"` or `"watching"` on a game page, `"settings"`
      on the settings page of a game, nil on another page.

  A user with more pages open has more activities. `activities/1` gives
  the one that tells the most. Guests are never tracked.

  A page that subscribes gets a `%Phoenix.Socket.Broadcast{event:
  "presence_diff"}` message on the `topic/0` when a user comes, leaves or
  changes the page.
  """
  use Phoenix.Presence, otp_app: :octomocto, pubsub_server: Octomocto.PubSub

  @topic "online_users"
  # The activity that tells the most comes first
  @order ["playing", "watching", "settings", nil]

  def topic, do: @topic

  def subscribe, do: Phoenix.PubSub.subscribe(Octomocto.PubSub, @topic)

  @doc "Tracks the process `pid` of the user with the activity."
  def track(pid, user_id, %{kind: _, doing: _} = activity) do
    {:ok, _ref} = track(pid, @topic, Integer.to_string(user_id), activity)
    :ok
  end

  @doc """
  The activity of each user of `user_ids` that is online, as a map by user
  id.
  """
  def activities(user_ids) do
    keys = MapSet.new(user_ids, &Integer.to_string/1)

    for {key, %{metas: metas}} <- list(@topic), MapSet.member?(keys, key), into: %{} do
      activity = metas |> Enum.min_by(&Enum.find_index(@order, fn d -> d == &1.doing end))
      {String.to_integer(key), Map.take(activity, [:kind, :doing])}
    end
  end
end
