defmodule OctomoctoWeb.HealthControllerTest do
  use OctomoctoWeb.ConnCase

  test "GET /health answers ok", %{conn: conn} do
    conn = get(conn, ~p"/health")

    assert text_response(conn, 200) == "ok"
  end
end
