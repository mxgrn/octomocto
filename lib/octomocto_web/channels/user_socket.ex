defmodule OctomoctoWeb.UserSocket do
  use Phoenix.Socket

  channel "astronaut:*", OctomoctoWeb.AstronautChannel
  channel "echo:*", OctomoctoWeb.EchoChannel
  channel "mahjong:*", OctomoctoWeb.MahjongChannel
  channel "memory:*", OctomoctoWeb.MemoryChannel
  channel "overlap:*", OctomoctoWeb.OverlapChannel
  channel "schulte:*", OctomoctoWeb.SchulteChannel
  channel "set:*", OctomoctoWeb.SetGameChannel
  channel "sudoku:*", OctomoctoWeb.SudokuChannel
  channel "trains:*", OctomoctoWeb.TrainsChannel

  @impl true
  # The session is nil when the browser does not send the `_csrf_token` param
  def connect(params, socket, connect_info) do
    {:ok,
     assign(socket,
       user_id: verify_user_token(params["user_token"]),
       guest_name: OctomoctoWeb.GuestName.from_session(connect_info[:session]),
       guest_id: OctomoctoWeb.GuestName.id_from_session(connect_info[:session]),
       browser_locale: OctomoctoWeb.GuestName.locale_from_session(connect_info[:session])
     )}
  end

  @salt "user socket"
  @max_age_s 14 * 24 * 60 * 60

  @doc "Signs the user id for the `user_token` connect param."
  def user_token(user_id), do: Phoenix.Token.sign(OctomoctoWeb.Endpoint, @salt, user_id)

  # A guest (or a bad token) gives nil
  defp verify_user_token(token) when is_binary(token) do
    case Phoenix.Token.verify(OctomoctoWeb.Endpoint, @salt, token, max_age: @max_age_s) do
      {:ok, user_id} -> user_id
      {:error, _reason} -> nil
    end
  end

  defp verify_user_token(_token), do: nil

  @impl true
  def id(_socket), do: nil
end
