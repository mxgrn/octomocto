defmodule Octomocto.OnlineUsersTest do
  use ExUnit.Case, async: true

  alias Octomocto.OnlineUsers

  # A page of the user: one process for each page
  defp page, do: spawn_link(fn -> receive do: (:never -> :ok) end)

  test "activities/1 gives the activity that tells the most, only for the given users" do
    user_id = System.unique_integer([:positive])
    other_id = System.unique_integer([:positive])
    OnlineUsers.track(page(), user_id, %{kind: nil, doing: nil})
    OnlineUsers.track(page(), user_id, %{kind: "memory", doing: "playing"})
    OnlineUsers.track(page(), other_id, %{kind: nil, doing: nil})

    assert OnlineUsers.activities([user_id]) == %{user_id => %{kind: "memory", doing: "playing"}}
  end
end
