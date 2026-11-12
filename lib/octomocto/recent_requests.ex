defmodule Octomocto.RecentRequests do
  @moduledoc """
  The last requests on this node, for the traffic page of the admins
  (/admin/traffic). Only in memory: a restart clears them.

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

  # A name that ends with "bot", "crawler" or "spider", followed by its
  # version: "Amazonbot/0.1". The version is required, so that a phone like
  # "CUBOT X30" and a link like "/support/amazonbot)" are not bot names.
  @bot_name ~r/([A-Za-z0-9_.-]*(?:bot|crawler|spider))\//i

  @doc "Gives the name that a bot gives in its `user_agent`, or nil."
  def bot_name(nil), do: nil

  def bot_name(user_agent) do
    case Regex.run(@bot_name, user_agent, capture: :all_but_first) do
      [name] -> name
      nil -> nil
    end
  end

  @doc """
  Adds the `summaries` of the nodes and groups the requests by user agent,
  the most requests first. A bot is grouped by its name (see `bot_name/1`),
  so that its versions are together. Other user agents are grouped by the
  full text.
  """
  def top_user_agents(summaries, limit \\ 100) do
    summaries
    |> Enum.reduce(%{}, &Map.merge(&2, &1, fn _ip, a, b -> add(a, b) end))
    |> Enum.flat_map(fn {ip, request} ->
      Enum.map(request.user_agents, fn {user_agent, count} -> {ip, user_agent, count} end)
    end)
    |> Enum.group_by(fn {_ip, user_agent, _count} ->
      case bot_name(user_agent) do
        nil -> {:full, user_agent}
        name -> {:bot, String.downcase(name)}
      end
    end)
    |> Enum.map(fn {key, requests} ->
      user_agents =
        requests
        |> Enum.group_by(&elem(&1, 1), &elem(&1, 2))
        |> Enum.map(fn {user_agent, counts} -> {user_agent, Enum.sum(counts)} end)
        |> Enum.sort_by(fn {_ua, count} -> -count end)

      {top_user_agent, _count} = hd(user_agents)

      %{
        name: if(match?({:bot, _}, key), do: bot_name(top_user_agent), else: top_user_agent),
        bot?: match?({:bot, _}, key),
        count: Enum.sum_by(requests, &elem(&1, 2)),
        ip_count: requests |> Enum.uniq_by(&elem(&1, 0)) |> length(),
        user_agents: user_agents
      }
    end)
    |> Enum.sort_by(&{-&1.count, &1.name || ""})
    |> Enum.take(limit)
  end
end
