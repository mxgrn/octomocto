defmodule OctomoctoWeb.OverlapImagesTest do
  use OctomoctoWeb.ConnCase, async: true

  test "the browser keeps the Overlap images for one week", %{conn: conn} do
    conn = get(conn, "/images/overlap/mix1/0.svg")

    assert response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["public, max-age=604800"]
  end
end
