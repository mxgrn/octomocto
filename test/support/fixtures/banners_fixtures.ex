defmodule Octomocto.BannersFixtures do
  @moduledoc """
  Test helpers for creating banners in `Octomocto.Banners`.
  """

  def banner_fixture(attrs \\ %{}) do
    {:ok, banner} =
      attrs
      |> Enum.into(%{text: "Hello", expires_at: DateTime.add(DateTime.utc_now(), 1, :day)})
      |> Octomocto.Banners.create_banner()

    banner
  end
end
