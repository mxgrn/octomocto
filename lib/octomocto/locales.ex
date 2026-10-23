defmodule Octomocto.Locales do
  @moduledoc """
  The browser locale of the players (users and guests), for example
  "pt-BR", only for statistics. It does not choose the language of the
  site.

  A game does not know the browsers of its players. So after a game saves
  its results, each player gets `{:results_saved}` (see `subscribe/2`),
  and the channel of the player writes the locale from its session (see
  `put/3`).
  """
  import Ecto.Query, only: [from: 2]

  alias Octomocto.Accounts.User
  alias Octomocto.Guests
  alias Octomocto.Guests.Guest
  alias Octomocto.Repo

  @doc """
  Subscribes the caller to `{:results_saved}` of a user, or of a guest when
  `user_id` is nil, on all nodes.
  """
  def subscribe(user_id, guest_id) do
    case topic(user_id, guest_id) do
      nil -> :ok
      topic -> Phoenix.PubSub.subscribe(Octomocto.PubSub, topic)
    end
  end

  @doc """
  Tells each player that its results are saved. Call it after
  `Octomocto.Guests.save/2`, so that the row of each guest is there.
  """
  def broadcast_saved(players) do
    for player <- players, topic = topic(player.user_id, Guests.guest_id(player)) do
      Phoenix.PubSub.broadcast(Octomocto.PubSub, topic, {:results_saved})
    end
  end

  @doc "Writes the locale of a user, or of a guest when `user_id` is nil."
  def put(user_id, _guest_id, locale) when user_id != nil do
    Repo.update_all(from(u in User, where: u.id == ^user_id), set: [locale: locale])
  end

  def put(nil, guest_id, locale) when guest_id != nil do
    Repo.update_all(from(g in Guest, where: g.id == ^guest_id), set: [locale: locale])
  end

  defp topic(user_id, _guest_id) when user_id != nil, do: "locale:user:#{user_id}"
  defp topic(nil, guest_id) when guest_id != nil, do: "locale:guest:#{guest_id}"
  defp topic(nil, nil), do: nil
end
