defmodule OctomoctoWeb.SentryFilter do
  @moduledoc """
  Removes events that are not app errors before Sentry sends them.

  When a client closes the connection during a response (for example, the
  user closes the tab while a static file loads), Bandit raises
  `Bandit.TransportError` with the `:closed` reason. The client is gone, so
  this is not a problem in the app.
  """

  def before_send(%Sentry.Event{original_exception: %Bandit.TransportError{error: :closed}}),
    do: nil

  def before_send(event), do: event
end
