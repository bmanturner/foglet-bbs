defmodule Foglet.Accounts.User do
  @moduledoc """
  User schema and changesets for the Accounts context.

  See `docs/DATA_MODEL.md` §1 for the authoritative field list and
  anonymization flow.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  # Public for test assertions and Plan 03 context code.
  @handle_format ~r/\A[A-Za-z0-9_-]+\z/
  @handle_min 2
  @handle_max 20
  @password_min 8
  @password_max 256

  @valid_roles [:user, :mod, :sysop]
  @valid_email_digests [:off, :daily, :weekly]

  schema "users" do
    field :handle, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :confirmed_at, :utc_datetime_usec

    field :role, Ecto.Enum, values: @valid_roles, default: :user

    field :location, :string
    field :tagline, :string
    field :real_name, :string

    field :post_count, :integer, default: 0
    field :last_seen_at, :utc_datetime_usec

    field :theme, :string, default: "default"
    field :show_in_last_callers, :boolean, default: true
    field :email_digest, Ecto.Enum, values: @valid_email_digests, default: :off
    field :preferences, :map, default: %{}

    field :deleted_at, :utc_datetime_usec

    has_many :ssh_keys, Foglet.Accounts.SSHKey
    has_many :user_tokens, Foglet.Accounts.UserToken

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for registering a new user.

  Required: :handle, :email, :password. Password is hashed via Argon2
  and stored in :password_hash; :password virtual field is cleared.
  """
  def registration_changeset(user \\ %__MODULE__{}, attrs) do
    user
    |> cast(attrs, [:handle, :email, :password])
    |> validate_required([:handle, :email, :password])
    |> validate_handle()
    |> validate_email()
    |> validate_password()
    |> put_password_hash()
    |> unsafe_validate_unique(:handle, FogletBbs.Repo)
    |> unsafe_validate_unique(:email, FogletBbs.Repo)
    |> unique_constraint(:handle)
    |> unique_constraint(:email)
  end

  @doc "Changeset for password reset — only changes :password."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password()
    |> put_password_hash()
  end

  @doc "Changeset for role changes — sysop pathway."
  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, @valid_roles)
  end

  @doc "Mark a user as confirmed (email verified OR sysop-created per D-02)."
  def confirm_changeset(user) do
    change(user, confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond))
  end

  @doc "Profile edit changeset. Never touches handle/email/password."
  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :location,
      :tagline,
      :real_name,
      :theme,
      :preferences,
      :show_in_last_callers,
      :email_digest
    ])
    |> validate_inclusion(:email_digest, @valid_email_digests)
  end

  @doc """
  Anonymization changeset — called by Foglet.Accounts.delete_user/1.

  Clears PII: email is randomized, location/tagline/real_name are nilled,
  password_hash is invalidated, deleted_at is set. See docs/DATA_MODEL.md §1.
  """
  def deletion_changeset(user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    change(user, %{
      deleted_at: now,
      location: nil,
      tagline: nil,
      real_name: nil,
      email: "deleted-#{user.id}@localhost",
      password_hash: "invalid-deleted",
      show_in_last_callers: false
    })
  end

  @doc "Public accessor for the handle format regex (used in tests)."
  def handle_format, do: @handle_format

  @doc "Public accessor for valid roles (used in Mix tasks and tests)."
  def valid_roles, do: @valid_roles

  # ---------- Private ----------

  defp validate_handle(changeset) do
    changeset
    |> validate_length(:handle, min: @handle_min, max: @handle_max)
    |> validate_format(:handle, @handle_format,
      message: "must be alphanumeric, underscore, or hyphen"
    )
  end

  defp validate_email(changeset) do
    changeset
    |> validate_length(:email, max: 254)
    |> validate_format(:email, ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/,
      message: "must be a valid email address"
    )
  end

  defp validate_password(changeset) do
    validate_length(changeset, :password, min: @password_min, max: @password_max)
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      password ->
        changeset
        |> put_change(:password_hash, Argon2.hash_pwd_salt(password))
        |> delete_change(:password)
    end
  end
end
