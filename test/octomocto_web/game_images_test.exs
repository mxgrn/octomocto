defmodule OctomoctoWeb.GameImagesTest do
  use OctomoctoWeb.ConnCase, async: true

  for path <- ["/images/overlap/mix1/0.svg", "/images/memory/animals/1.svg"] do
    test "the browser keeps #{path} for one week", %{conn: conn} do
      conn = get(conn, unquote(path))

      assert response(conn, 200)
      assert get_resp_header(conn, "cache-control") == ["public, max-age=604800"]
    end
  end
end
