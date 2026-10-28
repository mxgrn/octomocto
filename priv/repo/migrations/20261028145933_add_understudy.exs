defmodule Octomocto.Repo.Migrations.AddUnderstudy do
  use Ecto.Migration

  def up, do: Understudy.Migration.up()
  def down, do: Understudy.Migration.down()
end
