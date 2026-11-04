defmodule Octomocto.Notices do
  @moduledoc """
  One-line messages to a signed-in user or to a guest, for example an
  invite to a game. The bar at the top of each page shows them one at a
  time, in the order in which they came (see `OctomoctoWeb.Notices`).

  The recipient is `{:user, user_id}` or `{:guest, guest_id}` (the guest
  id in the session, see `OctomoctoWeb.GuestName`). A notice to a guest is
  only a message: never use a guest id for access.

  Nothing is stored: a page gets only the notices that come while it is
  open. A source that must keep its messages, for a user who is offline
  or for a reload, stores them itself and gives them to the page when it
  mounts.

  A notice is a map with:

    * `:id` - unique for the recipient, so that a notice that comes twice
      shows once,
    * `:text` - the line,
    * `:actions` - the buttons, each a map with an `:id`, a `:label` and
      an `:href` (nil for a button that only closes the notice). Each
      button closes the notice on all pages of the recipient.
    * `:expires_at` - the system time in milliseconds when the notice
      goes away by itself, or nil,
    * `:reply_to` (optional) - a PubSub topic. A click on a button sends
      `{:notice_answered, notice_id, action_id, recipient}` to it, so that
      the sender knows the answer.
    * `:sound` (optional) - `"invite"` plays the invite sound in the
      browser when the notice comes (see `assets/js/sounds.js`).

  For example, from a remote console:

      Octomocto.Notices.notify({:user, 42}, "The site restarts in 5 minutes.")
  """

  def topic({:user, user_id}), do: "notices:user:#{user_id}"
  def topic({:guest, guest_id}), do: "notices:guest:#{guest_id}"

  def subscribe(recipient), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, topic(recipient))

  @doc """
  Sends a notice with the `text` and an "OK" button to the recipient. The
  options are `:expires_in` (in milliseconds, by default it does not
  expire) and `:actions` (in place of the "OK" button). Gives the id of
  the notice.
  """
  def notify(recipient, text, opts \\ []) do
    id = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)
    expires_in = opts[:expires_in]

    push(recipient, %{
      id: id,
      text: text,
      actions: opts[:actions] || [%{id: "ok", label: "OK", href: nil}],
      expires_at: expires_in && System.system_time(:millisecond) + expires_in
    })

    id
  end

  @doc "Sends the notice to all pages of the recipient."
  def push(recipient, %{id: _, text: _, actions: _, expires_at: _} = notice) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(recipient), {:notice, notice})
  end

  @doc "Tells the sender of the notice which button the recipient clicked, if it asked."
  def answer(%{reply_to: topic, id: id}, action_id, recipient) when is_binary(topic) do
    Phoenix.PubSub.broadcast(
      Octomocto.PubSub,
      topic,
      {:notice_answered, id, action_id, recipient}
    )
  end

  def answer(_notice, _action_id, _recipient), do: :ok

  @doc "Closes the notice on all pages of the recipient."
  def dismiss(recipient, notice_id) do
    Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(recipient), {:notice_dismissed, notice_id})
  end
end
