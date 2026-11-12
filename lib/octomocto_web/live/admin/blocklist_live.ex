defmodule OctomoctoWeb.Admin.BlocklistLive do
  @moduledoc """
  The blocklist entries, with a form to add one or to change one. See
  `Octomocto.Blocklist`.
  """
  use OctomoctoWeb, :live_view

  alias Octomocto.Blocklist

  # The traffic page links here with the full user agent of a client, to cut
  # it to the name of the bot before blocking it.
  def mount(params, _session, socket) do
    user_agent = params["user_agent"]

    {:ok,
     socket
     |> assign(page_title: "Blocklist", noindex: true)
     |> assign(:prefilled?, user_agent != nil)
     |> assign(:editing, nil)
     |> assign(
       :form,
       to_form(Blocklist.change_entry(%Blocklist.Entry{}, %{user_agent: user_agent}))
     )
     |> stream(:entries, Blocklist.list_entries())}
  end

  def handle_event("validate", %{"entry" => params}, socket) do
    changeset = Blocklist.change_entry(socket.assigns.editing || %Blocklist.Entry{}, params)
    {:noreply, assign(socket, :form, to_form(changeset, action: :validate))}
  end

  def handle_event("save", %{"entry" => params}, socket) do
    result =
      if entry = socket.assigns.editing,
        do: Blocklist.update_entry(entry, params),
        else: Blocklist.create_entry(params)

    case result do
      {:ok, entry} ->
        # A changed entry stays in its place, a new one goes to the top
        at = if socket.assigns.editing, do: -1, else: 0
        {:noreply, socket |> stop_editing() |> stream_insert(:entries, entry, at: at)}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    entry = Blocklist.get_entry!(id)

    {:noreply,
     socket
     |> assign(:editing, entry)
     |> assign(:form, to_form(Blocklist.change_entry(entry)))}
  end

  def handle_event("cancel", _params, socket), do: {:noreply, stop_editing(socket)}

  def handle_event("delete", %{"id" => id}, socket) do
    {:ok, entry} = id |> Blocklist.get_entry!() |> Blocklist.delete_entry()

    socket =
      if socket.assigns.editing && socket.assigns.editing.id == entry.id,
        do: stop_editing(socket),
        else: socket

    {:noreply, stream_delete(socket, :entries, entry)}
  end

  defp stop_editing(socket) do
    socket
    |> assign(:editing, nil)
    |> assign(:form, to_form(Blocklist.change_entry()))
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} games_played={@games_played}>
      <div id="admin-blocklist" class="flex flex-col gap-6 pt-2 pb-4">
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
              Blocklist
            </h1>
            <p class="mt-1 text-sm text-base-content/60">
              These clients get a plain 404 for all pages. With an IP and a user agent, both must match.
            </p>
          </div>
          <.link
            id="traffic-link"
            navigate={~p"/admin/traffic"}
            class="inline-flex items-center gap-1.5 rounded-full px-4 py-2 text-sm font-semibold text-octo-indigo ring-1 ring-octo-indigo/30 transition hover:bg-octo-indigo/5 dark:text-octo-indigo-light"
          >
            <.icon name="hero-chart-bar-micro" class="size-4" /> Traffic
          </.link>
        </div>

        <.form
          for={@form}
          id="blocklist-form"
          phx-change="validate"
          phx-submit="save"
          class={[
            "grid gap-x-4 rounded-2xl bg-white p-4 shadow-sm ring-1 dark:bg-base-100 sm:grid-cols-2 transition",
            if(@editing, do: "ring-2 ring-octo-indigo/50", else: "ring-base-content/10")
          ]}
        >
          <p
            :if={@editing}
            class="mb-2 text-sm font-semibold text-octo-indigo sm:col-span-2 dark:text-octo-indigo-light"
          >
            Change the entry
          </p>
          <.input field={@form[:ip]} label="IP or CIDR range" placeholder="203.0.113.0/24" />
          <.input
            field={@form[:user_agent]}
            label="User agent contains"
            placeholder="python-requests"
            autofocus={@prefilled?}
          />
          <div class="sm:col-span-2">
            <.input field={@form[:note]} label="Note" placeholder="Why it is blocked" />
          </div>
          <div class="flex items-center gap-2 sm:col-span-2">
            <button
              id="add-entry"
              type="submit"
              phx-disable-with={if(@editing, do: "Saving…", else: "Blocking…")}
              class="inline-flex items-center gap-1.5 rounded-full bg-octo-indigo px-4 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
            >
              <%= if @editing do %>
                <.icon name="hero-check-micro" class="size-4" /> Save
              <% else %>
                <.icon name="hero-no-symbol-micro" class="size-4" /> Block
              <% end %>
            </button>
            <button
              :if={@editing}
              id="cancel-edit"
              type="button"
              phx-click="cancel"
              class="rounded-full px-4 py-2 text-sm font-semibold text-base-content/60 transition hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </button>
          </div>
        </.form>

        <ul id="entries" phx-update="stream" class="flex flex-col gap-3">
          <li
            id="entries-empty"
            class="hidden only:block rounded-2xl border border-dashed border-base-content/20 p-8 text-center text-sm text-base-content/60"
          >
            Nothing is blocked
          </li>
          <li
            :for={{id, entry} <- @streams.entries}
            id={id}
            class="flex items-start gap-4 rounded-2xl bg-white p-4 shadow-sm ring-1 ring-base-content/10 transition dark:bg-base-100"
          >
            <div class="min-w-0 flex-1 space-y-1.5">
              <div class="flex flex-wrap items-center gap-2 text-sm">
                <span class={[
                  "rounded-md px-2 py-0.5 font-mono",
                  if(entry.ip,
                    do:
                      "bg-octo-indigo/10 text-octo-indigo dark:bg-octo-indigo-light/15 dark:text-octo-indigo-light",
                    else: "bg-base-content/5 text-base-content/60"
                  )
                ]}>
                  {entry.ip || "Any IP"}
                </span>
                <span :if={entry.user_agent} class="text-base-content/40">+</span>
                <span
                  :if={entry.user_agent}
                  class="break-all rounded-md bg-base-content/5 px-2 py-0.5 font-mono text-base-content/80"
                >
                  {entry.user_agent}
                </span>
              </div>
              <p :if={entry.note} class="text-sm text-base-content/70">{entry.note}</p>
              <p class="text-xs text-base-content/50">
                {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M")} UTC
              </p>
            </div>
            <div class="flex shrink-0 items-center gap-1">
              <button
                id={"edit-entry-#{entry.id}"}
                type="button"
                aria-label="Edit"
                phx-click="edit"
                phx-value-id={entry.id}
                class="rounded-full p-2 text-base-content/60 transition hover:bg-base-content/5 hover:text-octo-indigo"
              >
                <.icon name="hero-pencil-square" class="size-5" />
              </button>
              <button
                id={"delete-entry-#{entry.id}"}
                type="button"
                aria-label="Delete"
                phx-click="delete"
                phx-value-id={entry.id}
                data-confirm="Unblock these clients?"
                class="rounded-full p-2 text-base-content/60 transition hover:bg-error/10 hover:text-error"
              >
                <.icon name="hero-trash" class="size-5" />
              </button>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end
end
