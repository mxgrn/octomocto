defmodule Octomocto.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :telegram_id, :integer
    field :telegram_username, :string
    field :name, :string
    # The name that other players see in games. Blank means a color name.
    field :display_name, :string
    field :avatar_url, :string
    # Copied from the session token (see `UserToken`). Nothing reads it now.
    field :authenticated_at, :utc_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  A user changeset for registering or changing the email.

  It requires the email to change otherwise an error is added.

  ## Options

    * `:validate_unique` - Set to false if you don't want to validate the
      uniqueness of the email, for example when the email of an other
      account can be merged into this one. Defaults to `true`.
  """
  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)
      |> validate_email_changed()

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Octomocto.Repo)
      |> unique_constraint(:email)
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  @doc """
  A user changeset for the data that we get from the Telegram Login Widget.

  The Telegram username and photo can change, so we update them on each
  sign-in. The name is set only when it is empty. The display name gets the
  Telegram first name only when it is empty, so a custom name stays.
  """
  def telegram_changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :telegram_username, :avatar_url])
    |> validate_required([:telegram_id])
    |> unique_constraint(:telegram_id)
    |> put_name_if_empty(attrs)
    |> put_display_name_if_empty(attrs)
  end

  @display_name_max 30

  @doc """
  A user changeset for changing the display name. A blank name is stored as nil.
  """
  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name])
    |> update_change(:display_name, &(&1 && String.trim(&1)))
    |> validate_length(:display_name, max: @display_name_max)
  end

  defp put_name_if_empty(changeset, attrs) do
    if get_field(changeset, :name) do
      changeset
    else
      cast(changeset, attrs, [:name])
    end
  end

  defp put_display_name_if_empty(changeset, attrs) do
    first_name = attrs[:first_name]

    if get_field(changeset, :display_name) || first_name in [nil, ""] do
      changeset
    else
      put_change(changeset, :display_name, truncate(first_name, @display_name_max))
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = DateTime.utc_now(:second)
    change(user, confirmed_at: now)
  end
end
