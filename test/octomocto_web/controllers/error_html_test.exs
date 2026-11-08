defmodule OctomoctoWeb.ErrorHTMLTest do
  use OctomoctoWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "an unknown page shows the 404 page with a link to the home page", %{conn: conn} do
    body = conn |> get("/no-such-page") |> html_response(404)

    link = body |> LazyHTML.from_document() |> LazyHTML.query("#not-found-home-link")
    assert LazyHTML.attribute(link, "href") == ["/"]
  end

  test "renders 500.html" do
    assert render_to_string(OctomoctoWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
