defmodule Octomocto.Guests do
  @moduledoc """
  The guests that finished a game (see `Octomocto.Guests.Guest`).
  """
  import Ecto.Query, only: [from: 2]

  alias Octomocto.Guests.Guest
  alias Octomocto.Repo

  @doc """
  Saves the guests among the players of a finished game, before their
  results: a result refers to its guest. Each player is a map with
  `:name`, and `:guest_id` when the player is a guest with an id. A guest
  that is already saved keeps its row. Then each saved guest gets
  `{:guest_saved, id}` (see `subscribe/1`).
  """
  def save(players, now) do
    rows =
      for %{guest_id: id, name: name} <- players, id != nil and name != nil do
        %{id: id, name: name, inserted_at: now}
      end

    Repo.insert_all(Guest, rows, on_conflict: :nothing, conflict_target: :id)

    for %{id: id} <- rows do
      Phoenix.PubSub.broadcast(Octomocto.PubSub, topic(id), {:guest_saved, id})
    end
  end

  @doc """
  Subscribes the caller to `{:guest_saved, id}` of the guest, sent after
  each game that saves the guest, on all nodes. The game does not know the
  browser of the guest, so the channel of the guest writes its locale (see
  `put_locale/2`).
  """
  def subscribe(id), do: Phoenix.PubSub.subscribe(Octomocto.PubSub, topic(id))

  @doc "Writes the browser locale of a saved guest, for example \"pt-BR\"."
  def put_locale(id, locale) do
    Repo.update_all(from(g in Guest, where: g.id == ^id), set: [locale: locale])
  end

  defp topic(id), do: "guest:#{id}"

  @doc """
  The guest id of a player for its result. It is nil for a user, for a
  player from before the guest ids, and for a guest without a name, which
  `save/2` does not save.
  """
  def guest_id(%{guest_id: id, name: name}) when name != nil, do: id
  def guest_id(_player), do: nil
end
