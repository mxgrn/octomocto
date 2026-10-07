defmodule OctomoctoWeb.UserSocket do
  use Phoenix.Socket

  channel "astronaut:*", OctomoctoWeb.AstronautChannel
  channel "schulte:*", OctomoctoWeb.SchulteChannel

  @impl true
  def connect(params, socket, _connect_info) do
    {:ok, assign(socket, :user_id, verify_user_token(params["user_token"]))}
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
