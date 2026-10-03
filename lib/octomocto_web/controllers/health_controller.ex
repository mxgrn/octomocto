defmodule OctomoctoWeb.HealthController do
  use OctomoctoWeb, :controller

  def show(conn, _params) do
    text(conn, "ok")
  end
end
