defmodule OctomoctoWeb.Admin.TopIpsLive do
  @moduledoc """
  The IPs of the last requests on all nodes (see `Octomocto.RecentRequests`),
  the most requests first, with buttons that add them to the blocklist.
  """
  use OctomoctoWeb, :live_view

  alias Octomocto.{Blocklist, RecentRequests}

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Top IPs", noindex: true)
     |> stream_configure(:ips, dom_id: &row_id(&1.ip))
     |> load()}
  end

  defp load(socket) do
    summaries = RecentRequests.cluster_summaries()
    ips = summaries |> RecentRequests.top_ips() |> Enum.map(&with_blocks/1)

    socket
    |> assign(:nodes, length(summaries))
    |> assign(:requests, summaries |> Enum.flat_map(&Map.values/1) |> Enum.sum_by(& &1.count))
    |> assign(:loaded_at, DateTime.utc_now())
    |> stream(:ips, ips, reset: true)
  end

  # Adds if the IP is blocked for all user agents, and for each user agent
  defp with_blocks(row) do
    {:ok, ip} = row.ip |> String.to_charlist() |> :inet.parse_address()

    user_agents =
      Enum.map(row.user_agents, fn {user_agent, count} ->
        %{user_agent: user_agent, count: count, blocked?: Blocklist.blocked?(ip, user_agent)}
      end)

    %{row | user_agents: user_agents} |> Map.put(:blocked?, Blocklist.blocked?(ip, nil))
  end

  @doc "Gives the DOM id of the row of the `ip` text."
  def row_id(ip), do: "ip-" <> (ip |> String.replace(".", "_") |> String.replace(":", "-"))

  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event("block", %{"ip" => ip} = params, socket) do
    attrs = %{ip: ip, user_agent: params["user_agent"], note: "From the top IPs page"}

    socket =
      case Blocklist.create_entry(attrs) do
        {:ok, _entry} ->
          put_flash(socket, :info, "Blocked #{blocked_text(attrs)}")

        {:error, changeset} ->
          {field, {message, _}} = hd(changeset.errors)
          put_flash(socket, :error, "Not blocked: #{field} #{message}")
      end

    # The cache of this node gets the entry through the PubSub
    _ = :sys.get_state(Blocklist.Cache)
    {:noreply, load(socket)}
  end

  defp blocked_text(%{ip: ip, user_agent: nil}), do: ip
  defp blocked_text(%{ip: ip, user_agent: user_agent}), do: "#{ip} with #{user_agent}"

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} games_played={@games_played}>
      <div id="admin-top-ips" class="flex flex-col gap-6 pt-2 pb-4">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div>
            <.link
              id="admin-link"
              navigate={~p"/admin"}
              class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
            >
              <.icon name="hero-chevron-left-micro" class="size-4" /> Admin
            </.link>
            <h1 class="text-2xl font-semibold tracking-tight text-octo-navy dark:text-base-content">
              Top IPs
            </h1>
            <p id="top-ips-summary" class="mt-1 text-sm text-base-content/60">
              The last {@requests} requests on {@nodes} {if @nodes == 1, do: "node", else: "nodes"}, at {Calendar.strftime(
                @loaded_at,
                "%H:%M:%S"
              )} UTC. Static files are not included.
            </p>
          </div>
          <div class="flex items-center gap-2">
            <.link
              id="blocklist-link"
              navigate={~p"/admin/blocklist"}
              class="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-octo-indigo ring-1 ring-octo-indigo/30 transition hover:bg-octo-indigo/5 dark:text-octo-indigo-light"
            >
              <.icon name="hero-no-symbol-micro" class="size-4" /> Blocklist
            </.link>
            <button
              id="refresh"
              type="button"
              phx-click="refresh"
              class="inline-flex items-center gap-1.5 rounded-full bg-octo-indigo px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
            >
              <.icon name="hero-arrow-path-micro" class="size-4 phx-click-loading:animate-spin" />
              Refresh
            </button>
          </div>
        </div>

        <ul id="ips" phx-update="stream" class="flex flex-col gap-3">
          <li
            id="ips-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/20 p-8 text-center text-sm text-base-content/60"
          >
            No requests yet
          </li>
          <li
            :for={{id, row} <- @streams.ips}
            id={id}
            class={[
              "flex flex-col gap-3 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-base-content/10 transition dark:bg-base-100",
              row.blocked? && "opacity-60"
            ]}
          >
            <div class="flex flex-wrap items-center gap-x-3 gap-y-2">
              <span
                data-role="count"
                class="min-w-12 rounded-lg bg-octo-indigo/10 px-2 py-1 text-center font-semibold tabular-nums text-octo-indigo dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light"
              >
                {row.count}
              </span>
              <span class="font-mono text-sm font-medium text-octo-navy dark:text-base-content">
                {row.ip}
              </span>
              <span
                :if={row.blocked?}
                data-role="blocked"
                class="rounded-full bg-error/10 px-2 py-0.5 text-xs font-semibold text-error"
              >
                Blocked
              </span>
              <span class="min-w-0 flex-1 truncate text-xs text-base-content/50">
                Last: {Calendar.strftime(row.last_at, "%H:%M:%S")} {row.last_path}
              </span>
              <button
                :if={!row.blocked?}
                type="button"
                data-role="block-ip"
                phx-click="block"
                phx-value-ip={row.ip}
                data-confirm={"Block #{row.ip} for all user agents?"}
                class="inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold text-error ring-1 ring-error/30 transition hover:bg-error/10"
              >
                <.icon name="hero-no-symbol-micro" class="size-3.5" /> Block IP
              </button>
            </div>
            <ul class="flex flex-col gap-1.5 border-t border-base-content/5 pt-3">
              <li
                :for={ua <- row.user_agents}
                class="flex items-start gap-3 text-xs"
              >
                <span class="w-10 shrink-0 text-right tabular-nums text-base-content/60">
                  {ua.count}
                </span>
                <span class={[
                  "min-w-0 flex-1 break-all font-mono",
                  if(ua.user_agent, do: "text-base-content/80", else: "italic text-base-content/50")
                ]}>
                  {ua.user_agent || "No user agent"}
                </span>
                <span
                  :if={ua.blocked? && !row.blocked?}
                  class="shrink-0 rounded-full bg-error/10 px-2 py-0.5 font-semibold text-error"
                >
                  Blocked
                </span>
                <button
                  :if={ua.user_agent && !ua.blocked?}
                  type="button"
                  data-role="block-ip-user-agent"
                  phx-click="block"
                  phx-value-ip={row.ip}
                  phx-value-user_agent={ua.user_agent}
                  data-confirm={"Block #{row.ip} only with this user agent?"}
                  class="shrink-0 rounded-full px-2 py-0.5 font-semibold text-error/80 transition hover:bg-error/10 hover:text-error"
                >
                  Block IP + user agent
                </button>
              </li>
            </ul>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
