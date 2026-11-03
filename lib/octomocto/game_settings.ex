defmodule Octomocto.GameSettings do
  @moduledoc """
  Keeps the settings that a user or a guest chose last, for each game, so
  that the settings page of the game shows them again (see
  `Octomocto.GameSettings.Saved`). A guest is found by the guest id in the
  session (see `OctomoctoWeb.GuestName`). The settings are only a
  convenience: never use them for authentication or access.
  """
  import Ecto.Query

  alias Octomocto.GameSettings.Saved
  alias Octomocto.Repo

  @doc """
  Gives the saved settings of the game for the scope's user, else for the
  guest, or nil.
  """
  def get(scope, guest_id, game) do
    case owner(scope, guest_id) do
      nil ->
        nil

      {field, id} ->
        from(s in Saved, where: s.game == ^game and field(s, ^field) == ^id, select: s.settings)
        |> Repo.one()
    end
  end

  @doc """
  Saves the settings of the game for the scope's user, else for the guest.
  The settings replace the settings that were saved before.
  """
  def put(scope, guest_id, game, settings) do
    case owner(scope, guest_id) do
      nil ->
        :ok

      {field, id} ->
        now = DateTime.utc_now()

        Repo.insert_all(
          Saved,
          [%{field => id, game: game, settings: settings, inserted_at: now, updated_at: now}],
          on_conflict: [set: [settings: settings, updated_at: now]],
          conflict_target: {:unsafe_fragment, "(#{field}, game) WHERE #{field} IS NOT NULL"}
        )

        :ok
    end
  end

  defp owner(%{user: %{id: id}}, _guest_id), do: {:user_id, id}
  defp owner(_scope, guest_id) when is_binary(guest_id), do: {:guest_id, guest_id}
  defp owner(_scope, _guest_id), do: nil
end
