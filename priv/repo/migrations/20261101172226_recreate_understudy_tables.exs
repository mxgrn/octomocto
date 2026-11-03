defmodule Octomocto.Repo.Migrations.RecreateUnderstudyTables do
  use Ecto.Migration

  # The new Understudy has other tables. The old translations are only a
  # cache, so we drop them and the LLM translates the texts again.
  #
  # On a new database, the previous migration already made the new tables,
  # because it calls the current `Understudy.Migration.up/0`.
  def up do
    drop_if_exists table(:understudy_translations)
    drop_if_exists table(:understudy_translation_claims)
    Understudy.Migration.up()
  end

  def down do
    Understudy.Migration.down()

    create table(:understudy_translations) do
      add :locale, :text, null: false
      add :domain, :text, null: false
      add :context, :text, null: false, default: ""
      add :text, :text, null: false
      add :plural_text, :text
      add :text_hash, :binary, null: false
      add :plural_index, :integer, null: false, default: 0
      add :value, :text, null: false

      timestamps()
    end

    create unique_index(:understudy_translations, [
             :locale,
             :domain,
             :context,
             :text_hash,
             :plural_index
           ])
  end
end
