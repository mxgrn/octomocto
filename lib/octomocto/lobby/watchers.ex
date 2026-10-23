defmodule Octomocto.Lobby.Watchers do
  @moduledoc """
  The processes that only watch a game, in the whole cluster. See
  `Octomocto.Lobby.watch/3` and `Octomocto.Lobby.watchers/1`.
  """
  use Phoenix.Presence, otp_app: :octomocto, pubsub_server: Octomocto.PubSub
end
