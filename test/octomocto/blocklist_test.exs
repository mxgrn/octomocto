defmodule Octomocto.BlocklistTest do
  use Octomocto.DataCase, async: true

  alias Octomocto.Blocklist

  # The cache is the same for all tests. Thus, each test uses its own IPs,
  # and removes its entries from the cache at the end.
  defp block(attrs) do
    {:ok, entry} = Blocklist.create_entry(attrs)
    on_exit(fn -> Blocklist.broadcast_deleted(entry.id) end)
    _ = :sys.get_state(Blocklist.Cache)
    entry
  end

  describe "create_entry/1" do
    test "keeps the IP in its normal text" do
      assert {:ok, %{ip: "203.0.113.0/24"}} = Blocklist.create_entry(%{ip: "203.0.113.9/24"})
    end

    test "needs an IP or a user agent" do
      assert {:error, changeset} = Blocklist.create_entry(%{note: "bot"})
      assert "set an IP, a user agent, or both" in errors_on(changeset).ip
    end

    test "rejects an invalid IP" do
      assert {:error, changeset} = Blocklist.create_entry(%{ip: "203.0.113"})
      assert "is not an IP or a CIDR range" in errors_on(changeset).ip
    end

    test "rejects a user agent shorter than 4 characters" do
      assert {:error, changeset} = Blocklist.create_entry(%{user_agent: "bot"})
      assert "should be at least 4 character(s)" in errors_on(changeset).user_agent
    end

    test "rejects a user agent that matches normal browsers, without an IP" do
      assert {:error, changeset} = Blocklist.create_entry(%{user_agent: "Chrome"})

      assert "matches normal browsers; keep only the bot name, or add an IP" in errors_on(
               changeset
             ).user_agent

      assert {:ok, _entry} = Blocklist.create_entry(%{ip: "203.0.113.7", user_agent: "Chrome"})
    end

    test "rejects a full user agent with browser parts, without an IP" do
      for user_agent <- [
            "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/99.0.1 Safari/537.36",
            "Mozilla/5.0 (compatible; SERankingBacklinksBot/1.0; +https://seranking.com/backlinks-crawler)"
          ] do
        assert {:error, changeset} = Blocklist.create_entry(%{user_agent: user_agent})

        assert "matches normal browsers; keep only the bot name, or add an IP" in errors_on(
                 changeset
               ).user_agent
      end

      assert {:ok, _entry} = Blocklist.create_entry(%{user_agent: "SERankingBacklinksBot"})
    end

    test "rejects the same IP and user agent again" do
      assert {:ok, _entry} = Blocklist.create_entry(%{ip: "203.0.113.7"})
      assert {:error, changeset} = Blocklist.create_entry(%{ip: "203.0.113.7"})
      assert "is already blocked" in errors_on(changeset).ip

      assert {:ok, _entry} = Blocklist.create_entry(%{ip: "203.0.113.7", user_agent: "curl"})
    end
  end

  describe "blocked?/2" do
    test "blocks an IP in a range" do
      block(%{ip: "198.51.100.0/24"})

      assert Blocklist.blocked?({198, 51, 100, 9}, "Mozilla/5.0")
      refute Blocklist.blocked?({198, 51, 101, 9}, "Mozilla/5.0")
    end

    test "blocks a user agent from any IP, case-insensitively" do
      block(%{user_agent: "UniqueBlocklistTestBot"})

      assert Blocklist.blocked?({192, 0, 2, 1}, "Mozilla/5.0 (uniqueblockListtestbot/1.0)")
      refute Blocklist.blocked?({192, 0, 2, 1}, "Mozilla/5.0")
      refute Blocklist.blocked?({192, 0, 2, 1}, nil)
    end

    test "with an IP and a user agent, blocks only when both match" do
      block(%{ip: "198.51.102.7", user_agent: "python-requests"})

      assert Blocklist.blocked?({198, 51, 102, 7}, "python-requests/2.32.3")
      refute Blocklist.blocked?({198, 51, 102, 7}, "Mozilla/5.0")
      refute Blocklist.blocked?({198, 51, 102, 8}, "python-requests/2.32.3")
    end

    test "blocks with the changed entry" do
      entry = block(%{ip: "198.51.104.7"})

      {:ok, _entry} = Blocklist.update_entry(entry, %{ip: "198.51.104.8"})
      _ = :sys.get_state(Blocklist.Cache)

      refute Blocklist.blocked?({198, 51, 104, 7}, nil)
      assert Blocklist.blocked?({198, 51, 104, 8}, nil)
    end

    test "finds if a user agent is blocked from any IP" do
      block(%{user_agent: "UserAgentBlockedTestBot"})
      block(%{ip: "198.51.105.7", user_agent: "OnlyWithIpTestBot"})

      assert Blocklist.user_agent_blocked?("x UserAgentBlockedTestBot/1.0")
      refute Blocklist.user_agent_blocked?("OnlyWithIpTestBot")
    end

    test "check/2 tells if the blocked request goes to the log" do
      block(%{ip: "198.51.106.7"})
      block(%{ip: "198.51.106.0/24", user_agent: "LoggedTestBot", log: :log})

      assert Blocklist.check({198, 51, 106, 7}, "Mozilla/5.0") == :quiet
      assert Blocklist.check({198, 51, 106, 7}, "LoggedTestBot/1.0") == :log
      assert Blocklist.check({198, 51, 107, 7}, "Mozilla/5.0") == nil
    end

    test "does not block after the entry is deleted" do
      entry = block(%{ip: "198.51.103.7"})

      {:ok, _entry} = Blocklist.delete_entry(entry)
      _ = :sys.get_state(Blocklist.Cache)

      refute Blocklist.blocked?({198, 51, 103, 7}, nil)
    end
  end
end
