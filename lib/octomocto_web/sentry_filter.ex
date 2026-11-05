defmodule OctomoctoWeb.SentryFilter do
  @moduledoc """
  Removes events that are not app errors before Sentry sends them.

  When a client closes the connection during a response (for example, the
  user closes the tab while a static file loads), Bandit raises
  `Bandit.TransportError` with the `:closed` reason. The client is gone, so
  this is not a problem in the app.

  `Plug.CSRFProtection.InvalidCSRFTokenError` occurs when a form has an old
  CSRF token (for example, the user signed in or out in a different tab) or
  when the browser does not send the session cookie. Plug shows a 403 page,
  and the app has no bug to fix.
  """

  def before_send(%Sentry.Event{original_exception: %Bandit.TransportError{error: :closed}}),
    do: nil

  def before_send(%Sentry.Event{
        original_exception: %Plug.CSRFProtection.InvalidCSRFTokenError{}
      }),
      do: nil

  def before_send(event), do: event
end
