defmodule Octomocto.Blocklist.Cache do
  @moduledoc """
  Keeps the blocklist entries of `Octomocto.Blocklist` in memory on this
  node, for the check on each request.

  At start, the process reads the entries from the database once. Then it
  applies the added and deleted entries from the PubSub, which come from
  all nodes. In the test environment, it does not read the database.

  The rules are in `:persistent_term`, so that a read is fast and does not
  go through this process. A write is costly, but the entries change rarely.
  """
  use GenServer

  alias Octomocto.{Blocklist, IpRange}

  @key {__MODULE__, :rules}

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Gives the rules: one `{range or nil, user agent pattern or nil}` for each entry."
  def rules, do: :persistent_term.get(@key, [])

  @impl true
  def init(_opts) do
    # Before the load, so that no change comes between the two unseen
    Blocklist.subscribe()
    {:ok, %{}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, entries) do
    entries =
      if Application.get_env(:octomocto, :load_blocklist, true),
        do: Map.new(Blocklist.list_entries(), &{&1.id, &1}),
        else: entries

    {:noreply, put(entries)}
  end

  @impl true
  def handle_info({:blocklist_added, entry}, entries),
    do: {:noreply, entries |> Map.put(entry.id, entry) |> put()}

  def handle_info({:blocklist_deleted, id}, entries),
    do: {:noreply, entries |> Map.delete(id) |> put()}

  defp put(entries) do
    rules = Enum.map(Map.values(entries), &{range(&1.ip), &1.user_agent})
    :persistent_term.put(@key, rules)
    entries
  end

  defp range(nil), do: nil

  defp range(ip) do
    {:ok, range} = IpRange.parse(ip)
    range
  end
end
