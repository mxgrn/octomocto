defmodule OctomoctoWeb.SentryFilter do
  @moduledoc """
  Removes events that are not app errors before Sentry sends them.

  When a client closes the connection during a response (for example, the
  user closes the tab while a static file loads), Bandit raises
  `Bandit.TransportError` with the `:closed` reason. The client is gone, so
  this is not a problem in the app.

  An exception with a 4xx status (see `Plug.Exception.status/1`) gives a
  client error page, for example `OctomoctoWeb.NotFoundError` for a profile
  that does not exist (404), or `Plug.CSRFProtection.InvalidCSRFTokenError`
  for a form with an old CSRF token (403). The app shows the correct page,
  and it has no bug to fix.
  """

  def before_send(%Sentry.Event{original_exception: %Bandit.TransportError{error: :closed}}),
    do: nil

  def before_send(%Sentry.Event{original_exception: exception} = event)
      when is_exception(exception) do
    if Plug.Exception.status(exception) in 400..499, do: nil, else: event
  end

  def before_send(event), do: event
end
