defmodule Octomocto.PublicId do
  @moduledoc """
  The id of a user or a guest in the URL of the profile page
  (`/players/:public_id`), so that the URL does not show the id in the
  database. It has 8 random letters and digits, for example "aZ3k9QxP":
  no "-" or "_", which look bad in a URL. It always has a capital
  letter, so it is never the same as a handle (see
  `Octomocto.Accounts.User.handle_changeset/2`).
  """

  @alphabet ~c"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
  @length 8

  @doc "Gives a new random public id."
  def generate do
    # 128 random bits for 8 digits of base 62 (about 48 bits): the digits
    # are as good as uniform
    id = :crypto.strong_rand_bytes(16) |> :binary.decode_unsigned() |> digits(@length, [])

    # About 1 id in 80 has no capital letter: try again
    if id =~ ~r/[A-Z]/, do: id, else: generate()
  end

  defp digits(_number, 0, acc), do: List.to_string(acc)

  defp digits(number, count, acc),
    do: digits(div(number, 62), count - 1, [Enum.at(@alphabet, rem(number, 62)) | acc])
end
