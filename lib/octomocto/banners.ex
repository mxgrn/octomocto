defmodule Octomocto.Banners do
  @moduledoc """
  The banners that admins write on the /admin pages. A banner
  is for all pages, or only for the pages of one game.

  A page shows one banner at a time: the first that the user did not
  close, in the order the banners were added. The browser keeps the
  closed banners (see `OctomoctoWeb.SiteBanners`). The closes
  are also in the database (see `Octomocto.Banners.Close`), for the
  statistics and so that a signed-in user does not see a closed
  banner again on other devices.
  """
  import Ecto.Query

  alias Octomocto.Accounts.Scope
  alias Octomocto.Guests
  alias Octomocto.Banners.{Close, Banner}
  alias Octomocto.Repo

  @doc "Gives all banners, also the expired ones, in the order they were added."
  def list_banners do
    Repo.all(from n in Banner, order_by: n.id)
  end

  @doc """
  Gives the banners that did not expire for the pages of the `game`
  (an id in `OctomoctoWeb.HomeLive.games/0`), in the order they were added.
  The site-wide banners are included. A nil `game` gives only the
  site-wide banners. For a signed-in user, the banners that the
  user closed are omitted.
  """
  def active_banners(game, scope \\ nil) do
    now = DateTime.utc_now()

    query =
      from n in Banner,
        where: n.expires_at > ^now,
        order_by: n.id

    query =
      if game,
        do: where(query, [n], is_nil(n.game) or n.game == ^game),
        else: where(query, [n], is_nil(n.game))

    scope
    |> omit_closed(query)
    |> Repo.all()
  end

  defp omit_closed(%Scope{user: %{id: user_id}}, query) do
    closed =
      from c in Close,
        where: c.banner_id == parent_as(:banner).id and c.user_id == ^user_id

    from n in query, as: :banner, where: not exists(closed)
  end

  defp omit_closed(_scope, query), do: query

  @doc """
  Saves that a user or a guest closed a banner. The `scope` gives
  the user. Without a user, the `guest` is `{id, name}` from the session,
  and the guest is saved first (see `Octomocto.Guests`). The first close is
  kept. A banner that does not exist is ignored.
  """
  def record_close(banner_id, scope, guest) do
    with %Banner{} <- Repo.get(Banner, banner_id),
         {field, id} <- closer(scope, guest) do
      Repo.insert_all(
        Close,
        [%{:banner_id => banner_id, field => id, :inserted_at => DateTime.utc_now()}],
        on_conflict: :nothing,
        conflict_target: {:unsafe_fragment, "(banner_id, #{field}) WHERE #{field} IS NOT NULL"}
      )
    end

    :ok
  end

  defp closer(%Scope{user: %{id: id}}, _guest), do: {:user_id, id}

  defp closer(_scope, {id, name}) when is_binary(id) and is_binary(name) do
    Guests.save([%{guest_id: id, name: name}], DateTime.utc_now())
    {:guest_id, id}
  end

  defp closer(_scope, _guest), do: nil

  @doc "Gives the number of closes of each banner, as a map from the banner id."
  def close_counts do
    from(c in Close, group_by: c.banner_id, select: {c.banner_id, count(c.id)})
    |> Repo.all()
    |> Map.new()
  end

  def get_banner!(id), do: Repo.get!(Banner, id)

  def create_banner(attrs) do
    %Banner{}
    |> Banner.changeset(attrs)
    |> Repo.insert()
  end

  def update_banner(%Banner{} = banner, attrs) do
    banner
    |> Banner.changeset(attrs)
    |> Repo.update()
  end

  def delete_banner(%Banner{} = banner), do: Repo.delete(banner)

  @doc """
  Translates the text of a banner into all languages other than
  English with the LLM (see `config :understudy`). Understudy translates in
  the background. Call it when an admin saves a banner, so that the
  translations are ready before the pages ask for them.
  """
  def translate(%Banner{text: text}) do
    if Application.get_env(:octomocto, :translate_banners, true) do
      Task.Supervisor.start_child(Octomocto.TaskSupervisor, fn ->
        OctomoctoWeb.Locale.other_locales()
        |> Enum.each(&Understudy.translate(text, locale: &1, domain: "banners"))
      end)
    end

    :ok
  end

  @doc """
  Gives the text of a banner in the language of the process. If the
  translation is not ready yet, or the LLM failed, it gives the English text.
  """
  def localized_text(%Banner{text: text}) do
    Understudy.translate(text,
      locale: Gettext.get_locale(OctomoctoWeb.Gettext),
      domain: "banners"
    )
  end

  def change_banner(%Banner{} = banner, attrs \\ %{}) do
    Banner.changeset(banner, attrs)
  end
end
