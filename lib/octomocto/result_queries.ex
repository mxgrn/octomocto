defmodule Octomocto.ResultQueries do
  @moduledoc "Query parts that the results of all games use."
  import Ecto.Query

  @doc """
  Limits a query of results to the results of the users `user_ids`. With
  nil, the query stays the same: the results of all users.
  """
  def of_users(query, nil), do: query
  def of_users(query, user_ids), do: where(query, [r], r.user_id in ^user_ids)
end
