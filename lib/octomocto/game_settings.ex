defmodule Octomocto.GameSettings do
  @moduledoc """
  Keeps the settings that a user or a guest chose last, for each game, so
  that the settings page of the game shows them again (see
  `Octomocto.GameSettings.Saved`), and the tab of the game page that they
  used last. A guest is found by the guest id in the
  session (see `OctomoctoWeb.GuestName`). The settings are only a
  convenience: never use them for authentication or access.
  """
  import Ecto.Query

  alias Octomocto.GameSettings.Saved
  alias Octomocto.Repo

  # The key of the tab in the saved map. The other keys are the settings.
  @tab "tab"

  @doc """
  Gives the saved settings of the game for the scope's user, else for the
  guest, or nil.
  """
  def get(scope, guest_id, game) do
    case saved(scope, guest_id, game) |> Map.delete(@tab) do
      settings when settings == %{} -> nil
      settings -> settings
    end
  end

  @doc """
  Gives the tab of the game page that the scope's user, else the guest,
  used last, for example "lobby", or nil.
  """
  def get_tab(scope, guest_id, game), do: saved(scope, guest_id, game)[@tab]

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
  The settings replace the settings that were saved before. The saved tab
  stays.
  """
  def put(scope, guest_id, game, settings) do
    upsert(scope, guest_id, game, settings, fn now ->
      from(s in Saved,
        update: [
          set: [
            settings:
              fragment(
                "jsonb_strip_nulls(EXCLUDED.settings || jsonb_build_object(?::text, ?->?))",
                @tab,
                s.settings,
                @tab
              ),
            updated_at: ^now
          ]
        ]
      )
    end)
  end

  @doc """
  Saves the tab of the game page that the scope's user, else the guest,
  used last. The saved settings stay.
  """
  def put_tab(scope, guest_id, game, tab) do
    upsert(scope, guest_id, game, %{@tab => tab}, fn now ->
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
