defmodule OctomoctoWeb.GuestNameTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias OctomoctoWeb.GuestName

  defp browser_locale(accept_language) do
    conn(:get, "/")
    |> init_test_session(%{})
    |> Plug.Conn.put_req_header("accept-language", accept_language)
    |> GuestName.call([])
    |> Plug.Conn.get_session()
    |> GuestName.locale_from_session()
  end

  test "the session keeps the first language of the browser" do
    assert browser_locale("pt-BR,pt;q=0.9,en;q=0.8") == "pt-BR"
  end

  test "the session keeps no language for any language" do
    assert browser_locale("*") == nil
  end
end
