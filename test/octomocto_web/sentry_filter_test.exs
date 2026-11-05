defmodule OctomoctoWeb.SentryFilterTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.SentryFilter

  test "drops a transport error from a closed connection" do
    error = %Bandit.TransportError{message: "Unrecoverable error: closed", error: :closed}
    event = Sentry.Event.transform_exception(error, [])

    assert SentryFilter.before_send(event) == nil
  end

  test "drops an invalid CSRF token error" do
    event = Sentry.Event.transform_exception(%Plug.CSRFProtection.InvalidCSRFTokenError{}, [])

    assert SentryFilter.before_send(event) == nil
  end

  test "drops a not found error" do
    event = Sentry.Event.transform_exception(%OctomoctoWeb.NotFoundError{}, [])

    assert SentryFilter.before_send(event) == nil
  end

  test "keeps a message event without an exception" do
    event = Sentry.Event.create_event(message: "boom")

    assert SentryFilter.before_send(event) == event
  end

  test "keeps other errors" do
    event = Sentry.Event.transform_exception(%RuntimeError{message: "boom"}, [])

    assert SentryFilter.before_send(event) == event
  end
end
