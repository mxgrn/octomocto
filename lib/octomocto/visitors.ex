defmodule Octomocto.Visitors do
  @moduledoc """
  All visitors that have a page of the site open, in the whole cluster:
  signed-in users and guests. Only for the count in the footer (see
  `OctomoctoWeb.Visitors`). The friends and the invites use
  `Octomocto.OnlineUsers`, which has only the users, with an activity.

  Each LiveView page and each game channel tracks its process with the key
  of the visitor (see `key/2`). A visitor with more pages open counts as one.
  A controller page does not track its visitor.

  A page that subscribes gets a `%Phoenix.Socket.Broadcast{event:
  "presence_diff"}` message on the `topic/0` when a visitor comes or leaves.
  """
  use Phoenix.Presence, otp_app: :octomocto, pubsub_server: Octomocto.PubSub

  @topic "visitors"

  def topic, do: @topic

  def subscribe, do: Phoenix.PubSub.subscribe(Octomocto.PubSub, @topic)

  @doc """
  The key of a visitor: the user id for a signed-in user, else the guest id.
  Nil when there is neither.
  """
  def key(user_id, _guest_id) when is_integer(user_id), do: "user:#{user_id}"
  def key(nil, guest_id) when is_binary(guest_id), do: "guest:#{guest_id}"
  def key(nil, nil), do: nil

  @doc "Tracks the process `pid` of the visitor. Does nothing for a nil key."
  def track(_pid, nil), do: :ok

  def track(pid, key) do
    {:ok, _ref} = track(pid, @topic, key, %{})
    :ok
  end

  @doc "The number of visitors."
  def count, do: map_size(list(@topic))

  @doc "True when the visitor has a page open."
  def online?(key), do: Map.has_key?(list(@topic), key)
end
