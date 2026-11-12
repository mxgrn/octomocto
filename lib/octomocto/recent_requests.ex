defmodule Octomocto.RecentRequests do
  @moduledoc """
  The last requests on this node, for the top IPs page of the admins
  (/admin/top-ips). Only in memory: a restart clears them.

  The requests are in a ring of `size` places in a public ETS table: the
  request process writes its request in the next place, over the oldest
  request. This process only owns the table.
  """
  use GenServer

  @default_size 5_000
  # Limits for the memory of one request
  @max_user_agent 300
  @max_path 200

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {name, Keyword.get(opts, :size, @default_size)}, name: name)
  end

  @impl true
  def init({table, size}) do
    :ets.new(table, [:set, :public, :named_table, write_concurrency: true])
    :ets.insert(table, [{:size, size}, {:next, -1}])
    {:ok, table}
  end

  @doc "Keeps one request with the client `ip` tuple and the `user_agent` (or nil)."
  def record(table \\ __MODULE__, ip, user_agent, method, path) do
    [{:size, size}] = :ets.lookup(table, :size)
    place = rem(:ets.update_counter(table, :next, 1), size)
    ip = ip |> :inet.ntoa() |> to_string()

    :ets.insert(
      table,
      {{:request, place}, ip, cut(user_agent, @max_user_agent), method, cut(path, @max_path),
       DateTime.utc_now()}
    )

    :ok
  end

  defp cut(nil, _max), do: nil
  defp cut(text, max), do: String.slice(text, 0, max)

  @doc """
  Groups the requests in the `table` of this node by IP:
  `%{ip => %{count:, user_agents: %{user_agent => count}, last_at:, last_path:}}`.
  """
  def summary(table \\ __MODULE__) do
    table
    |> :ets.match({{:request, :_}, :"$1", :"$2", :_, :"$3", :"$4"})
    |> Enum.reduce(%{}, fn [ip, user_agent, path, at], acc ->
      request = %{count: 1, user_agents: %{user_agent => 1}, last_at: at, last_path: path}
      Map.update(acc, ip, request, &add(&1, request))
    end)
  end

  defp add(a, b) do
    last = if DateTime.after?(b.last_at, a.last_at), do: b, else: a

    %{
      count: a.count + b.count,
      user_agents: Map.merge(a.user_agents, b.user_agents, fn _ua, x, y -> x + y end),
      last_at: last.last_at,
      last_path: last.last_path
    }
  end

  @doc "Gets the summaries of all nodes in the cluster."
  def cluster_summaries do
    [node() | Node.list()]
    |> :erpc.multicall(__MODULE__, :summary, [], 5_000)
    |> Enum.flat_map(fn
      {:ok, summary} -> [summary]
      _error -> []
    end)
  end

  @doc """
  Adds the `summaries` of the nodes and gives the IPs with the most requests
  first. The user agents of an IP are also in the order of their counts.
  """
  def top_ips(summaries, limit \\ 100) do
    summaries
    |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _ip, a, b -> add(a, b) end))
    |> Enum.map(fn {ip, request} ->
      user_agents = Enum.sort_by(request.user_agents, fn {_ua, count} -> -count end)
      Map.merge(request, %{ip: ip, user_agents: user_agents})
    end)
    |> Enum.sort_by(&{-&1.count, &1.ip})
    |> Enum.take(limit)
  end
end
