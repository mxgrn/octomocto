defmodule Octomocto.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Octomocto.Repo

  alias Octomocto.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by Telegram ID.
  """
  def get_user_by_telegram_id(telegram_id) do
    Repo.get_by(User, telegram_id: telegram_id)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets the user with the given email, or registers a new one.

  Sign-in and sign-up use the same form, so a new email registers a user.
  """
  def get_or_register_user(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> register_user(%{email: email})
      user -> {:ok, user}
    end
  end

  ## Telegram

  @doc """
  Signs in with the verified data from the Telegram Login Widget.

  Registers a new user if no user has this Telegram ID.
  """
  def sign_in_with_telegram(%{telegram_id: telegram_id} = attrs) do
    (get_user_by_telegram_id(telegram_id) || %User{})
    |> User.telegram_changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Connects a Telegram account to the user.

  If a different user already has this Telegram ID, the two users are merged,
  and the older user stays. Returns the user that stays.
  """
  def connect_telegram(%User{telegram_id: nil} = user, %{telegram_id: telegram_id} = attrs) do
    Repo.transact(fn ->
      case get_user_by_telegram_id(telegram_id) do
        nil -> user |> User.telegram_changeset(attrs) |> Repo.update()
        other -> merge_users(user, other)
      end
    end)
  end

  def connect_telegram(%User{}, _attrs), do: {:error, :conflict}

  ## Merging

  @doc """
  Returns true if the two users can be merged into one.

  The users can be merged only if they do not both have an email and do not
  both have a Telegram account.
  """
  def mergeable?(%User{} = a, %User{} = b) do
    a.id != b.id && !(a.email && b.email) && !(a.telegram_id && b.telegram_id)
  end

  # The older user stays. It gets the values that it does not have yet from
  # the newer user, and the newer user is deleted. When other tables refer to
  # users, their rows must move to the older user here.
  defp merge_users(a, b) do
    if mergeable?(a, b) do
      [older, newer] = Enum.sort_by([a, b], & &1.id)

      fields = [:email, :confirmed_at, :telegram_id, :telegram_username, :name, :avatar_url]

      changes =
        for field <- fields,
            is_nil(Map.get(older, field)),
            into: %{},
            do: {field, Map.get(newer, field)}

      Repo.delete!(newer)

      older
      |> Ecto.Changeset.change(changes)
      |> Repo.update()
    else
      {:error, :conflict}
    end
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  An email of a different user is accepted if the two users can be merged.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    changeset = User.email_changeset(user, attrs, validate_unique: false)
    other = changeset.valid? && get_user_by_email(Ecto.Changeset.get_change(changeset, :email))

    if other && !mergeable?(user, other) do
      Ecto.Changeset.add_error(changeset, :email, "has already been taken")
    else
      changeset
    end
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  If a different user has this email, the two users are merged, and the
  older user stays. Returns the user that stays.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(where(query, user_id: ^user.id)),
           {:ok, user} <- put_email(user, email),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        {:error, :conflict} -> {:error, :conflict}
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  defp put_email(user, email) do
    result =
      case get_user_by_email(email) do
        nil -> Repo.update(User.email_changeset(user, %{email: email}))
        other -> merge_users(user, other)
      end

    # The user has just confirmed the email with the link
    with {:ok, %User{confirmed_at: nil} = user} <- result do
      Repo.update(User.confirm_changeset(user))
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.

  There are two cases to consider:

  1. The user has already confirmed their email. They are logged in
     and the magic link is expired.

  2. The user has not confirmed their email. In this case, the user gets
     confirmed, logged in, and all tokens - including session ones - are
     expired. In theory, no other tokens exist but we delete all of them
     for best security practices.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
