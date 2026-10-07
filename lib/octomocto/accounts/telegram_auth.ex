defmodule Octomocto.Accounts.TelegramAuth do
  @moduledoc """
  Verifies the data that the Telegram Login Widget sends to us.

  See https://core.telegram.org/widgets/login#checking-authorization
  """

  # Someone who gets the redirect URL (for example, from the browser
  # history) can use it again until it expires.
  @max_age_in_seconds 24 * 60 * 60

  @doc """
  Verifies the widget params with the bot token.

  Returns `{:ok, attrs}` with the user attributes, or `{:error, :invalid}`.
  """
  def verify(params, bot_token \\ bot_token()) do
    {hash, data} = Map.pop(params, "hash")

    with true <- is_binary(hash),
         true <- Plug.Crypto.secure_compare(sign(data, bot_token), String.downcase(hash)),
         true <- fresh?(data["auth_date"]) do
      {:ok, to_attrs(data)}
    else
      _ -> {:error, :invalid}
    end
  end

  @doc """
  Signs the widget data in the same way as Telegram does.
  """
  def sign(data, bot_token) do
    data_check_string =
      data
      |> Enum.sort()
      |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)

    secret_key = :crypto.hash(:sha256, bot_token)

    :crypto.mac(:hmac, :sha256, secret_key, data_check_string)
    |> Base.encode16(case: :lower)
  end

  def bot_token, do: Application.fetch_env!(:octomocto, :telegram)[:bot_token]

  def bot_username, do: Application.fetch_env!(:octomocto, :telegram)[:bot_username]

  defp fresh?(auth_date) when is_binary(auth_date) do
    case Integer.parse(auth_date) do
      {timestamp, ""} -> System.os_time(:second) - timestamp <= @max_age_in_seconds
      _ -> false
    end
  end

  defp fresh?(_auth_date), do: false

  defp to_attrs(data) do
    name =
      [data["first_name"], data["last_name"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    %{
      telegram_id: data["id"],
      telegram_username: data["username"],
      name: name,
      first_name: data["first_name"],
      avatar_url: data["photo_url"]
    }
  end
end
