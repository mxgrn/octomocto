defmodule OctomoctoWeb.GuestName do
  @moduledoc """
  Keeps the indices of the guest name (see `Octomocto.GuestName`) and a
  random guest id in the session, and assigns the name as `:guest_name`.
  Each visitor gets a name and an id, so a user that signs out keeps the
  same guest name and id.

  The guest id is only for statistics and for the names in the results
  (see `Octomocto.Guests.Guest`). Never use it for authentication or
  access.

  Use the plug in the browser pipeline, and `on_mount/4` in a `live_session`.
  The `OctomoctoWeb.UserSocket` reads the name and the id from the session
  too.
  """
  import Plug.Conn

  alias Octomocto.GuestName

  @key "guest_name"
  @id_key "guest_id"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      if get_session(conn, @id_key),
        do: conn,
        else: put_session(conn, @id_key, Ecto.UUID.generate())

    case GuestName.name(get_session(conn, @key)) do
      nil ->
        indices = GuestName.random()

        conn
        |> put_session(@key, indices)
        |> assign(:guest_name, GuestName.name(indices))

      name ->
        assign(conn, :guest_name, name)
    end
  end

  def on_mount(:default, _params, session, socket) do
    {:cont, Phoenix.Component.assign(socket, :guest_name, from_session(session))}
  end

  @doc "The guest name in a session, or nil when it has no valid name."
  def from_session(session) when is_map(session), do: GuestName.name(session[@key])
  def from_session(_session), do: nil

  @doc "The guest id in a session, or nil."
  def id_from_session(session) when is_map(session), do: session[@id_key]
  def id_from_session(_session), do: nil

  @doc "The session keys of the guest, to keep them when the session is renewed."
  def keys, do: [@key, @id_key]
end
