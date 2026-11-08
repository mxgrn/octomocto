defmodule Octomocto.PublicIdTest do
  use ExUnit.Case, async: true

  alias Octomocto.PublicId

  test "generate/0 never gives an id that can be a handle" do
    # A handle has no capital letters (see `Octomocto.Accounts.User`), so
    # an id with one is never the same as a handle
    for _ <- 1..2000 do
      id = PublicId.generate()
      assert id =~ ~r/^[0-9A-Za-z]{8}$/
      assert id =~ ~r/[A-Z]/
    end
  end
end
