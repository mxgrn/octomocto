defmodule Octomocto.Accounts.TelegramAuthTest do
  use ExUnit.Case, async: true

  import Octomocto.AccountsFixtures

  alias Octomocto.Accounts.TelegramAuth

  test "returns the user attributes for signed params" do
    params = telegram_params(%{"id" => "42", "first_name" => "Ada", "last_name" => "Lovelace"})

    assert {:ok, %{telegram_id: "42", name: "Ada Lovelace"}} = TelegramAuth.verify(params)
  end

  test "rejects params with a wrong hash" do
    params = %{telegram_params() | "id" => "1"}

    assert TelegramAuth.verify(params) == {:error, :invalid}
  end

  test "rejects params without a hash" do
    params = Map.delete(telegram_params(), "hash")

    assert TelegramAuth.verify(params) == {:error, :invalid}
  end

  test "rejects params older than one day" do
    two_days_ago = System.os_time(:second) - 2 * 24 * 60 * 60
    params = telegram_params(%{"auth_date" => to_string(two_days_ago)})

    assert TelegramAuth.verify(params) == {:error, :invalid}
  end
end
