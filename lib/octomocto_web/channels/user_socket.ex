defmodule OctomoctoWeb.UserSocket do
  use Phoenix.Socket

  channel "astronaut:*", OctomoctoWeb.AstronautChannel
  channel "schulte:*", OctomoctoWeb.SchulteChannel

  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end
