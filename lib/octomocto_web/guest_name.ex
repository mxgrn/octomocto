defmodule OctomoctoWeb.GuestName do
  @moduledoc """
  Keeps the indices of the guest name (see `Octomocto.GuestName`) in the
  session, and assigns the name as `:guest_name`. Each visitor gets a name,
  so a user that signs out keeps the same guest name.

  Use the plug in the browser pipeline, and `on_mount/4` in a `live_session`.
  The `OctomoctoWeb.UserSocket` reads the name from the session too.
  """
  import Plug.Conn

  alias Octomocto.GuestName

  @key "guest_name"

  def init(opts), do: opts

  def call(conn, _opts) do
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

  @doc "The session key of the guest name, to keep it when the session is renewed."
  def key, do: @key
end
