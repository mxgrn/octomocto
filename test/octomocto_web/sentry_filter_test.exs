defmodule OctomoctoWeb.SentryFilterTest do
  use ExUnit.Case, async: true

  alias OctomoctoWeb.SentryFilter

  test "drops a transport error from a closed connection" do
    error = %Bandit.TransportError{message: "Unrecoverable error: closed", error: :closed}
    event = Sentry.Event.transform_exception(error, [])

    assert SentryFilter.before_send(event) == nil
  end

  test "keeps other errors" do
    event = Sentry.Event.transform_exception(%RuntimeError{message: "boom"}, [])

    assert SentryFilter.before_send(event) == event
  end
end
