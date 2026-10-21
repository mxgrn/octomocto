defmodule OctomoctoWeb.NotFoundError do
  @moduledoc """
  Gives a 404 page, for example for a page that the user may not see.
  """
  defexception message: "not found", plug_status: 404
end
