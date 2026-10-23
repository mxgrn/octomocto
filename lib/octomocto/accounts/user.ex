defmodule Octomocto.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :confirmed_at, :utc_datetime
    field :telegram_id, :integer
    field :telegram_username, :string
    field :name, :string
    # The name that other players see in games. A random ocean name until
    # the user changes it (see `Octomocto.GuestName`), never blank.
    field :display_name, :string
    field :avatar_url, :string
    # The tab of the Memory page that the user used last: "free" or
    # "campaign". Nil means Free play.
    field :memory_tab, :string
    # The same for the Trains page
    field :trains_tab, :string
    # The first language of the browser in the last finished game, for
    # example "pt-BR" (see `Octomocto.Locales`). Only for statistics.
    field :locale, :string
    # Only admins can open the /admin pages. Set it in the database.
    field :role, Ecto.Enum, values: [:user, :admin], default: :user
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
  Telegram first name only when it is empty, so a custom name stays. With
  no first name, it gets a random ocean name.
  """
  def telegram_changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :telegram_username, :avatar_url])
    |> validate_required([:telegram_id])
    |> unique_constraint(:telegram_id)
    |> put_name_if_empty(attrs)
    |> put_display_name_if_empty(attrs)
    |> put_random_display_name_if_empty()
  end

  @doc "A changeset for a new user that signs in with the email. The display name is a random ocean name."
  def registration_changeset(user, attrs) do
    user
    |> email_changeset(attrs)
    |> put_random_display_name_if_empty()
  end

  @display_name_max 30

  @doc """
  A user changeset for changing the display name. A blank name changes to a
  new random ocean name, so that other players never see the email.
  """
  def display_name_changeset(user, attrs) do
    user
    |> cast(attrs, [:display_name], empty_values: [])
    |> update_change(:display_name, &(&1 && String.trim(&1)))
    |> put_random_display_name_if_empty()
    |> validate_length(:display_name, max: @display_name_max)
  end

  defp put_random_display_name_if_empty(changeset) do
    if get_field(changeset, :display_name) in [nil, ""],
      do: put_change(changeset, :display_name, Octomocto.GuestName.random_name()),
      else: changeset
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
