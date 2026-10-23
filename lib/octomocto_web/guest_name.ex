defmodule OctomoctoWeb.GuestName do
  @moduledoc """
  Keeps the indices of the guest name (see `Octomocto.GuestName`) and a
  random guest id in the session, and assigns the name as `:guest_name`.
  Each visitor gets a name and an id, so a user that signs out keeps the
  same guest name and id. The session also keeps the first language of
  the browser (`Accept-Language`), for the locale of the guest (see
  `Octomocto.Guests.put_locale/2`).

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
  @locale_key "guest_locale"

  def init(opts), do: opts

  def call(conn, _opts) do
    conn =
      if get_session(conn, @id_key),
        do: conn,
        else: put_session(conn, @id_key, Ecto.UUID.generate())

    conn = put_locale(conn)

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

  # Only a change of the language writes the session again
  defp put_locale(conn) do
    case {browser_locale(conn), get_session(conn, @locale_key)} do
      {nil, _saved} -> conn
      {locale, locale} -> conn
      {locale, _saved} -> put_session(conn, @locale_key, locale)
    end
  end

  # The first language tag, for example "pt-BR" in "pt-BR,pt;q=0.9,en;q=0.8"
  defp browser_locale(conn) do
    with [header | _] <- get_req_header(conn, "accept-language"),
         [tag | _] <- String.split(header, [",", ";"], parts: 2),
         tag = String.trim(tag),
         true <- Regex.match?(~r/^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8}){0,3}$/, tag) do
      tag
    else
      _ -> nil
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

  @doc "The browser locale in a session, or nil."
  def locale_from_session(session) when is_map(session), do: session[@locale_key]
  def locale_from_session(_session), do: nil

  @doc "The session keys of the guest, to keep them when the session is renewed."
  def keys, do: [@key, @id_key, @locale_key]
end
