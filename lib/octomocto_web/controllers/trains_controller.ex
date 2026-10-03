defmodule OctomoctoWeb.TrainsController do
  use OctomoctoWeb, :controller

  def index(conn, _params) do
    render(conn, :index)
  end
end
