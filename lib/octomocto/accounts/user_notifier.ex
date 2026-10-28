defmodule Octomocto.Accounts.UserNotifier do
  import Swoosh.Email

  alias Octomocto.Mailer
  alias Octomocto.Accounts.{User, UserToken}

  # A real inbox, so that people can reply to the emails
  @sender "hi@octomocto.com"

  # Delivers the email using the application mailer. Each email has an HTML body
  # with a button, and a text body for mail apps that do not show HTML.
  defp deliver(recipient, subject, content) do
    content = Map.put_new(content, :requested, nil)

    email =
      new()
      |> to(recipient)
      |> from({"Octomocto", @sender})
      |> reply_to(@sender)
      |> subject(subject)
      |> html_body(html(content))
      |> text_body(text(content))

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc """
  Deliver instructions to update a user email.
  """
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Confirm your new Octomocto email", %{
      heading: "Confirm your new email",
      message: "Click the button to change your Octomocto email to #{user.email}.",
      button: "Change email",
      url: url,
      validity: "#{UserToken.change_email_validity_in_days()} days",
      ignore: "If you did not ask for this change, you can ignore this email."
    })
  end

  @doc """
  Deliver instructions to log in with a magic link.
  """
  def deliver_login_instructions(user, url, device \\ nil) do
    requested = requested(DateTime.utc_now(), device)

    case user do
      %User{confirmed_at: nil} -> deliver_confirmation_instructions(user, url, requested)
      _ -> deliver_magic_link_instructions(user, url, requested)
    end
  end

  defp deliver_magic_link_instructions(user, url, requested) do
    deliver(user.email, "Your Octomocto sign-in link", %{
      heading: "Sign in to Octomocto",
      message: "You asked for a sign-in link at #{site()}. Click the button to sign in.",
      requested: requested,
      button: "Sign in",
      url: url,
      validity: "#{UserToken.magic_link_validity_in_hours()} hours",
      ignore: "If you did not ask for this email, you can ignore it."
    })
  end

  defp deliver_confirmation_instructions(user, url, requested) do
    deliver(user.email, "Your Octomocto sign-in link", %{
      heading: "Welcome to Octomocto",
      message:
        "You asked for a sign-in link at #{site()}. Click the button to confirm your email and sign in.",
      requested: requested,
      button: "Confirm and sign in",
      url: url,
      validity: "#{UserToken.magic_link_validity_in_hours()} hours",
      ignore: "If you did not create an account with us, you can ignore this email."
    })
  end

  # For example "Requested on 28 October 2026 at 14:05 UTC from Chrome on macOS."
  defp requested(time, device) do
    from = if device, do: " from #{device}"
    "Requested on #{Calendar.strftime(time, "%-d %B %Y at %H:%M UTC")}#{from}."
  end

  defp site, do: OctomoctoWeb.Endpoint.host()

  defp text(content) do
    """
    #{content.heading}

    #{content.message}

    #{content.button}:
    #{content.url}

    The link works for #{content.validity}.
    #{if content.requested, do: content.requested <> "\n"}#{content.ignore}

    --
    Octomocto · #{site()}
    Questions? Write to #{@sender}.
    """
  end

  # Mail apps support only simple HTML: tables for the layout and inline styles.
  # Gmail does not show SVG images, so the logo is a PNG.
  defp html(content) do
    c = Map.new(content, fn {key, value} -> {key, escape(value)} end)
    logo_url = escape(OctomoctoWeb.Endpoint.static_url() <> "/images/email-logo.png")
    site = escape(site())
    site_url = escape(OctomoctoWeb.Endpoint.url())
    font = "-apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif"

    """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
      </head>
      <body style="margin:0;padding:0;background-color:#EEF0FA;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#EEF0FA;">
          <tr>
            <td align="center" style="padding:40px 16px;">
              <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background-color:#ffffff;border-radius:16px;">
                <tr>
                  <td style="padding:40px 32px;font-family:#{font};color:#171532;">
                    <img src="#{logo_url}" width="209" height="33" alt="Octomocto" style="display:block;border:0;margin:0 0 32px;">
                    <h1 style="margin:0 0 12px;font-size:24px;line-height:32px;font-weight:600;">#{c.heading}</h1>
                    <p style="margin:0 0 28px;font-size:16px;line-height:24px;color:#4a4866;">#{c.message}</p>
                    <table role="presentation" cellpadding="0" cellspacing="0">
                      <tr>
                        <td style="border-radius:12px;background-color:#1A9FCB;">
                          <a href="#{c.url}" style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:600;color:#ffffff;text-decoration:none;border-radius:12px;">#{c.button}</a>
                        </td>
                      </tr>
                    </table>
                    <p style="margin:28px 0 0;font-size:14px;line-height:20px;color:#4a4866;">The link works for #{c.validity}.</p>
                    #{if content.requested, do: ~s(<p style="margin:4px 0 0;font-size:14px;line-height:20px;color:#4a4866;">#{c.requested}</p>)}
                    <p style="margin:16px 0 0;font-size:13px;line-height:20px;color:#8a88a3;">Or copy this link:<br><a href="#{c.url}" style="color:#8a88a3;word-break:break-all;">#{c.url}</a></p>
                  </td>
                </tr>
              </table>
              <p style="max-width:480px;margin:20px auto 0;font-family:#{font};font-size:13px;line-height:20px;color:#8a88a3;">#{c.ignore}</p>
              <p style="max-width:480px;margin:16px auto 0;font-family:#{font};font-size:13px;line-height:20px;color:#8a88a3;">Octomocto · <a href="#{site_url}" style="color:#8a88a3;">#{site}</a><br>Questions? Write to <a href="mailto:#{@sender}" style="color:#8a88a3;">#{@sender}</a>.</p>
            </td>
          </tr>
        </table>
      </body>
    </html>
    """
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
