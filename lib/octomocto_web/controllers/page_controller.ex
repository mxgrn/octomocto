defmodule OctomoctoWeb.PageController do
  use OctomoctoWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def elm(conn, _params) do
    render(conn, :elm)
  end

  def penguin(conn, _params) do
    render(conn, :penguin)
  end
end
