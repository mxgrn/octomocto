defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  def elm(conn, _params) do
    render(conn, :elm)
  end
end
