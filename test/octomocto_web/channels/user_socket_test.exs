defmodule OctomoctoWeb.UserSocketTest do
  use OctomoctoWeb.ChannelCase, async: true

  import ExUnit.CaptureLog

  alias OctomoctoWeb.UserSocket

  test "a socket without a session logs it" do
    log =
      capture_log(fn ->
        {:ok, _socket} =
          connect(UserSocket, %{"_csrf_token" => "old"},
            connect_info: %{session: nil, user_agent: "Safari"}
          )
      end)

    assert log =~ ~s(Socket without session: csrf_token=sent user=guest user_agent="Safari")
  end

  test "a socket with a session logs nothing" do
    log =
      capture_log(fn ->
        {:ok, _socket} = connect(UserSocket, %{}, connect_info: %{session: %{}})
      end)

    refute log =~ "Socket without session"
  end
end
