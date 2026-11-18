defmodule Octomocto.GameSettings do
  @moduledoc """
  Keeps the settings that a user or a guest chose last, for each game, so
  that the settings page of the game shows them again (see
  `Octomocto.GameSettings.Saved`). It also keeps other choices of the game
  page (see `@page_keys`), for example the tab that was used last. A guest
  is found by the guest id in the session (see `OctomoctoWeb.GuestName`).
  The settings are only a convenience: never use them for authentication
  or access.
  """
  import Ecto.Query

  alias Octomocto.GameSettings.Saved
  alias Octomocto.Repo

  # The keys of the other choices of the game page in the saved map: the
  # tab that was used last, and the theme choice of the Memory campaign.
  # The other keys are the settings.
  @page_keys ["tab", "campaign_theme"]

  @doc """
  Gives the saved settings of the game for the scope's user, else for the
  guest, or nil.
  """
  def get(scope, guest_id, game) do
    case saved(scope, guest_id, game) |> Map.drop(@page_keys) do
      settings when settings == %{} -> nil
      settings -> settings
    end
  end

  @doc """
  Gives the saved value of the `key` (see `@page_keys`) of the game page
  for the scope's user, else for the guest, or nil. For example, the tab
  is "lobby".
  """
  def get_value(scope, guest_id, game, key) when key in @page_keys,
    do: saved(scope, guest_id, game)[key]

  defp saved(scope, guest_id, game) do
    case owner(scope, guest_id) do
      nil ->
        %{}

      {field, id} ->
        from(s in Saved, where: s.game == ^game and field(s, ^field) == ^id, select: s.settings)
        |> Repo.one()
        |> Kernel.||(%{})
    end
  end

  @doc """
  Saves the settings of the game for the scope's user, else for the guest.
  The settings replace the settings that were saved before. The saved
  values of the game page (see `put_value/5`) stay.
  """
  def put(scope, guest_id, game, settings) do
    upsert(scope, guest_id, game, settings, fn now ->
      from(s in Saved,
        update: [
          set: [
            settings:
              fragment(
                """
                EXCLUDED.settings || (SELECT coalesce(jsonb_object_agg(key, value), '{}')
                FROM jsonb_each(?) WHERE key = ANY(?))
                """,
                s.settings,
                type(^@page_keys, {:array, :string})
              ),
            updated_at: ^now
          ]
        ]
      )
    end)
  end

  @doc """
  Saves the value of the `key` (see `@page_keys`) of the game page for the
  scope's user, else for the guest. The saved settings stay.
  """
  def put_value(scope, guest_id, game, key, value) when key in @page_keys do
    upsert(scope, guest_id, game, %{key => value}, fn now ->
      from(s in Saved,
        update: [
          set: [settings: fragment("? || EXCLUDED.settings", s.settings), updated_at: ^now]
        ]
      )
    end)
  end

  defp upsert(scope, guest_id, game, settings, on_conflict) do
    case owner(scope, guest_id) do
      nil ->
        :ok

      {field, id} ->
        now = DateTime.utc_now()

        Repo.insert_all(
          Saved,
          [%{field => id, game: game, settings: settings, inserted_at: now, updated_at: now}],
          on_conflict: on_conflict.(now),
          conflict_target: {:unsafe_fragment, "(#{field}, game) WHERE #{field} IS NOT NULL"}
        )

        :ok
    end
  end

  defp owner(%{user: %{id: id}}, _guest_id), do: {:user_id, id}
  defp owner(_scope, guest_id) when is_binary(guest_id), do: {:guest_id, guest_id}
  defp owner(_scope, _guest_id), do: nil
end
