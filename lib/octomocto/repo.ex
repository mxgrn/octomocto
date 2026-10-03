defmodule Octomocto.Repo do
  use Ecto.Repo,
    otp_app: :octomocto,
    adapter: Ecto.Adapters.Postgres
end
