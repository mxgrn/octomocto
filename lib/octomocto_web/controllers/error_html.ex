defmodule OctomoctoWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  See config/config.exs.
  """
  use OctomoctoWeb, :html

  # Each page in error_html/ is a full HTML document. Error pages do not use
  # the root layout, because the root layout needs the assigns of the browser
  # pipeline, which do not exist when no route matches.
  embed_templates "error_html/*"

  # For all other errors, a plain text page based on the template name.
  # For example, "500.html" becomes "Internal Server Error".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
