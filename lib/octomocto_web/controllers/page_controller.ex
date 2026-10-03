defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
