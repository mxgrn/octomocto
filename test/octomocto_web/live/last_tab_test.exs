defmodule OctomoctoWeb.LastTabTest do
  use OctomoctoWeb.ConnCase

  import Phoenix.LiveViewTest

  setup %{conn: conn} do
    %{conn: init_test_session(conn, %{"guest_id" => Ecto.UUID.generate()})}
  end

  for path <- ~w(/memory /trains) do
    test "#{path} opens the Lobby tab again for a guest", %{conn: conn} do
      {:ok, _view, _html} = live(conn, unquote(path) <> "/lobby")

      assert {:error, {_, %{to: to}}} = live(conn, unquote(path))
      assert to == unquote(path) <> "/lobby"
    end
  end
end
