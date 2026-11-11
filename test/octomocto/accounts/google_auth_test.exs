defmodule Octomocto.Accounts.GoogleAuthTest do
  use ExUnit.Case, async: true

  import Octomocto.AccountsFixtures
  alias Octomocto.Accounts.GoogleAuth

  @redirect_uri "http://localhost/auth/google/callback"

  describe "authorize_url/2" do
    test "asks Google for the basic scopes and gives back the state" do
      query =
        GoogleAuth.authorize_url(@redirect_uri, "the-state")
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()

      assert %{
               "client_id" => "test-client-id",
               "redirect_uri" => @redirect_uri,
               "response_type" => "code",
               "scope" => "openid email profile",
               "state" => "the-state"
             } = query
    end
  end

  describe "fetch_user/2" do
    test "exchanges the code and returns the user attributes" do
      Req.Test.stub(GoogleAuth, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert %{"code" => "the-code", "redirect_uri" => @redirect_uri} = URI.decode_query(body)

        token =
          google_id_token(%{
            "sub" => "123",
            "email" => "ada@example.com",
            "name" => "Ada Lovelace",
            "picture" => "https://example.com/ada.png"
          })

        Req.Test.json(conn, %{"id_token" => token})
      end)

      assert GoogleAuth.fetch_user("the-code", @redirect_uri) ==
               {:ok,
                %{
                  google_id: "123",
                  email: "ada@example.com",
                  name: "Ada Lovelace",
                  avatar_url: "https://example.com/ada.png"
                }}
    end

    test "rejects an email that Google did not verify" do
      stub_google_token(%{"email_verified" => false})

      assert GoogleAuth.fetch_user("the-code", @redirect_uri) == {:error, :invalid}
    end

    test "rejects a token for a different client" do
      stub_google_token(%{"aud" => "other-client-id"})

      assert GoogleAuth.fetch_user("the-code", @redirect_uri) == {:error, :invalid}
    end

    test "returns an error when Google rejects the code" do
      Req.Test.stub(GoogleAuth, fn conn ->
        conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "invalid_grant"})
      end)

      assert GoogleAuth.fetch_user("the-code", @redirect_uri) == {:error, :invalid}
    end
  end
end
