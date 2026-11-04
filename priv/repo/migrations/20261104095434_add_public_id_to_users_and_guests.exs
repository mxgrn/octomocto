defmodule Octomocto.Repo.Migrations.AddPublicIdToUsersAndGuests do
  use Ecto.Migration

  @alphabet "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"

  # 8 random letters and digits, as `Octomocto.PublicId`. The subquery
  # refers to the row, so that it runs again for each row.
  defp random_id(table) do
    """
    (SELECT string_agg(substr('#{@alphabet}', 1 + floor(random() * 62)::int, 1), '')
     FROM generate_series(1, 8)
     WHERE #{table}.id IS NOT NULL)
    """
  end

  def up do
    for table <- [:users, :guests] do
      alter table(table) do
        add :public_id, :string
      end

      flush()
      execute "UPDATE #{table} SET public_id = #{random_id(table)}"

      alter table(table) do
        modify :public_id, :string, null: false
      end

      create unique_index(table, [:public_id])
    end
  end

  def down do
    for table <- [:users, :guests] do
      alter table(table) do
        remove :public_id
      end
    end
  end
end
