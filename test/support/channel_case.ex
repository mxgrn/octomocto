defmodule OctomoctoWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by
  channel tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Import conveniences for testing with channels
      import Phoenix.ChannelTest
      import OctomoctoWeb.ChannelCase

      # The default endpoint for testing
      @endpoint OctomoctoWeb.Endpoint
    end
  end

  setup tags do
    Octomocto.DataCase.setup_sandbox(tags)
    :ok
  end
end
