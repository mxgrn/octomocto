defmodule Octomocto.Blocklist do
  @moduledoc """
  The clients that get a 404 for all requests (see `OctomoctoWeb.BlockRequests`).
  Admins edit the entries on /admin/blocklist and /admin/traffic.

  The entries are in the database. Each node also keeps them in memory
  (see `Octomocto.Blocklist.Cache`), so that a request does not query the
  database. A change goes to the caches of all nodes through the PubSub.
  """
  import Ecto.Query

  alias Octomocto.Blocklist.{Cache, Entry}
  alias Octomocto.Repo

  @topic "blocklist"

  @doc "Gives all entries, the newest first."
  def list_entries do
    Repo.all(from e in Entry, order_by: [desc: e.id])
  end

  def get_entry!(id), do: Repo.get!(Entry, id)

  def change_entry(entry \\ %Entry{}, attrs \\ %{}), do: Entry.changeset(entry, attrs)

  def create_entry(attrs) do
    with {:ok, entry} <- %Entry{} |> Entry.changeset(attrs) |> Repo.insert() do
      broadcast({:blocklist_put, entry})
      {:ok, entry}
    end
  end

  def update_entry(%Entry{} = entry, attrs) do
    with {:ok, entry} <- entry |> Entry.changeset(attrs) |> Repo.update() do
      broadcast({:blocklist_put, entry})
      {:ok, entry}
    end
  end

  def delete_entry(%Entry{} = entry) do
    with {:ok, entry} <- Repo.delete(entry) do
      broadcast_deleted(entry.id)
      {:ok, entry}
    end
  end

  @doc """
  Removes the entry with the `id` from the caches of all nodes. The tests
  also use it, because the database sandbox does not clear the caches.
  """
  def broadcast_deleted(id), do: broadcast({:blocklist_deleted, id})

  @doc "Gets the changes of the entries."
  def subscribe, do: Phoenix.PubSub.subscribe(Octomocto.PubSub, @topic)

  defp broadcast(message), do: Phoenix.PubSub.broadcast(Octomocto.PubSub, @topic, message)

  @doc """
  Gives true when an entry blocks the client with the `ip` tuple and the
  `user_agent` header (nil when it is missing). An entry with an IP and a
  user agent blocks only when both match.
  """
  def blocked?(ip, user_agent) do
    Enum.any?(Cache.rules(), fn {range, pattern} ->
      (is_nil(range) or Octomocto.IpRange.member?(range, ip)) and
        (is_nil(pattern) or Entry.matches_user_agent?(pattern, user_agent))
    end)
  end

  @doc """
  Gives true when an entry without an IP blocks the `user_agent` from any IP.
  """
  def user_agent_blocked?(user_agent) do
    Enum.any?(Cache.rules(), fn {range, pattern} ->
      is_nil(range) and pattern != nil and Entry.matches_user_agent?(pattern, user_agent)
    end)
  end
end
