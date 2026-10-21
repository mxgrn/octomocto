defmodule Octomocto.DataMigrations do
  @moduledoc """
  One-off changes of the data, to run by hand in the console of the running
  app after the deploy that needs them. Each one is safe to run again.
  """

  import Ecto.Query

  alias Octomocto.Accounts.User
  alias Octomocto.{GuestName, Repo}

  @doc """
  Gives each user without a display name a random ocean name, so that other
  players never see a part of the email. Gives the number of changed users.
  """
  def add_random_display_names do
    users = Repo.all(from u in User, where: is_nil(u.display_name) or u.display_name == "")

    for user <- users do
      user |> Ecto.Changeset.change(display_name: GuestName.random_name()) |> Repo.update!()
    end

    length(users)
  end
end
