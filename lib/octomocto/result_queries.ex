defmodule Octomocto.ResultQueries do
  @moduledoc "Query parts that the results of all games use."
  import Ecto.Query

  @doc """
  Limits a query of results to the results of the users `user_ids`. With
  nil, the query stays the same: the results of all users.
  """
  def of_users(query, nil), do: query
  def of_users(query, user_ids), do: where(query, [r], r.user_id in ^user_ids)

  @trend_size 30

  @doc """
  Gives the `field` values of the latest 30 results of `query`, the oldest
  first, for a sparkline. Each item is `%{id: id, value: value}`.
  """
  def trend(query, field) do
    from(r in query,
      order_by: [desc: r.inserted_at],
      limit: @trend_size,
      select: %{id: r.id, value: field(r, ^field)}
    )
    |> Octomocto.Repo.all()
    |> Enum.reverse()
  end
end
