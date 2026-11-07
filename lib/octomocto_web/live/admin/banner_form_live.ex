defmodule OctomoctoWeb.Admin.BannerFormLive do
  @moduledoc "The form to add a banner or to change one."
  use OctomoctoWeb, :live_view

  alias Octomocto.Banners
  alias Octomocto.Banners.Banner
  alias OctomoctoWeb.Admin.BannersLive
  alias OctomoctoWeb.HomeLive

  def mount(params, _session, socket) do
    banner = banner(socket.assigns.live_action, params)

    {:ok,
     socket
     |> assign(
       page_title: page_title(socket.assigns.live_action),
       noindex: true,
       banner: banner,
       game_options: [
         {BannersLive.pages_name(nil), ""}
         | Enum.map(HomeLive.games(), &{&1.name, &1.id})
       ]
     )
     |> assign_form(Banners.change_banner(banner))}
  end

  # A new banner expires in a week, at the start of the hour
  defp banner(:new, _params) do
    expires_at =
      DateTime.utc_now()
      |> DateTime.add(7, :day)
      |> Map.merge(%{minute: 0, second: 0, microsecond: {0, 0}})

    %Banner{expires_at: expires_at}
  end

  defp banner(:edit, %{"id" => id}), do: Banners.get_banner!(id)

  defp page_title(:new), do: "New banner"
  defp page_title(:edit), do: "Edit banner"

  def handle_event("validate", %{"banner" => params}, socket) do
    changeset = Banners.change_banner(socket.assigns.banner, params)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("save", %{"banner" => params}, socket) do
    case save(socket.assigns.live_action, socket.assigns.banner, params) do
      {:ok, banner} ->
        Banners.translate(banner)

        {:noreply,
         socket
         |> put_flash(:info, "Banner saved")
         |> push_navigate(to: ~p"/admin/banners")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(:new, _banner, params), do: Banners.create_banner(params)

  defp save(:edit, banner, params),
    do: Banners.update_banner(banner, params)

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope} games_played={@games_played}>
      <div id="admin-banner" class="flex flex-col gap-6 pt-2 pb-4">
        <div>
          <.link
            id="banners-link"
            navigate={~p"/admin/banners"}
            class="inline-flex items-center gap-1 text-sm text-base-content/60 transition hover:text-base-content"
          >
            <.icon name="hero-chevron-left-micro" class="size-4" /> Banners
          </.link>
          <h1 class="text-2xl font-semibold tracking-tight text-octo-navy dark:text-base-content">
            {@page_title}
          </h1>
        </div>

        <.form
          for={@form}
          id="banner-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-4 rounded-2xl bg-base-100 p-5 shadow-sm ring-1 ring-base-content/10 sm:p-6"
        >
          <.input
            field={@form[:text]}
            type="text"
            label="Text (Markdown, on one line)"
            placeholder="Try the new [Overlap](/overlap) game!"
            autocomplete="off"
          />
          <.input field={@form[:game]} type="select" label="Pages" options={@game_options} />
          <.input field={@form[:expires_at]} type="datetime-local" label="Expires at (UTC)" />

          <div class="flex items-center justify-end gap-3 pt-2">
            <.link
              navigate={~p"/admin/banners"}
              class="rounded-full px-4 py-2 text-sm font-medium text-base-content/70 transition hover:bg-base-content/5 hover:text-base-content"
            >
              Cancel
            </.link>
            <button
              id="save-banner"
              type="submit"
              phx-disable-with="Saving..."
              class="rounded-full bg-octo-indigo px-5 py-2 text-sm font-semibold text-white shadow-sm transition hover:shadow-md hover:shadow-octo-indigo/20 active:scale-95"
            >
              Save
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end
end
