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
  @valid_statuses [:active, :pending, :rejected, :suspended]
  @default_timezone "Etc/UTC"
  @default_time_format "12h"
  @default_theme_id "gray"
  @default_handle_color "#FFFFFF"
  @handle_color_format ~r/\A#[0-9A-Fa-f]{6}\z/

  schema "users" do
    field :handle, :string
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :confirmed_at, :utc_datetime_usec

    field :role, Ecto.Enum, values: @valid_roles, default: :user
    field :status, Ecto.Enum, values: @valid_statuses, default: :active

    field :location, :string
    field :tagline, :string
    field :real_name, :string

    field :post_count, :integer, default: 0
    field :last_seen_at, :utc_datetime_usec

    field :timezone, :string, default: @default_timezone
    field :theme, :string, default: @default_theme_id
    field :handle_color, :string, default: @default_handle_color
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
    |> normalize_identity_fields()
    |> validate_required([:handle, :email, :password])
    |> validate_handle()
    |> validate_email()
    |> validate_password()
    |> Foglet.Accounts.IdentityPolicy.validate_registration_changeset()
    |> put_account_defaults()
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
    |> cast(
      attrs,
      [
        :location,
        :tagline,
        :real_name,
        :theme,
        :handle_color,
        :preferences,
        :show_in_last_callers,
        :email_digest,
        :timezone
      ],
      empty_values: []
    )
    |> normalize_private_profile_fields()
    |> merge_preferences(user.preferences)
    |> validate_length(:location, max: 80)
    |> validate_length(:tagline, max: 120)
    |> validate_length(:real_name, max: 120)
    |> validate_inclusion(:email_digest, @valid_email_digests)
    |> validate_timezone()
    |> validate_time_format()
    |> validate_theme()
    |> normalize_handle_color()
    |> validate_handle_color()
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

  @doc """
  Changeset for sysop status changes.

  Valid transitions are enforced by `Foglet.Accounts`: pending -> active,
  pending -> rejected, active -> suspended, and suspended -> active.
  """
  def status_changeset(user, attrs) do
    user
    |> cast(attrs, [:status])
    |> validate_required([:status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  @doc "Public accessor for the handle format regex (used in tests)."
  def handle_format, do: @handle_format

  @doc "Public accessor for the maximum handle length."
  def handle_max, do: @handle_max

  @doc "Public accessor for valid roles (used in Mix tasks and tests)."
  def valid_roles, do: @valid_roles

  defp normalize_identity_fields(changeset) do
    changeset
    |> update_change(:handle, &String.trim/1)
    |> update_change(:email, &String.trim/1)
  end

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

  defp put_account_defaults(changeset) do
    changeset
    |> put_change(:timezone, default_timezone())
    |> put_change(:theme, @default_theme_id)
    |> put_change(:handle_color, @default_handle_color)
    |> put_change(:preferences, default_preferences())
  end

  defp default_preferences do
    %{"time_format" => @default_time_format}
  end

  defp default_timezone do
    configured = Application.get_env(:foglet_bbs, :default_timezone)

    if is_binary(configured) and Timex.Timezone.exists?(configured) do
      configured
    else
      with local_timezone <- Timex.Timezone.local(),
           name when is_binary(name) <- Timex.Timezone.name_of(local_timezone),
           true <- Timex.Timezone.exists?(name) do
        name
      else
        _ -> @default_timezone
      end
    end
  end

  defp normalize_private_profile_fields(changeset) do
    changeset
    |> update_change(:location, &blank_to_nil/1)
    |> update_change(:tagline, &blank_to_nil/1)
    |> update_change(:real_name, &blank_to_nil/1)
  end

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(value), do: value

  defp merge_preferences(changeset, existing_preferences) do
    case get_change(changeset, :preferences) do
      nil ->
        changeset

      incoming_preferences when is_map(incoming_preferences) ->
        merged_preferences =
          existing_preferences
          |> normalize_preferences()
          |> Map.merge(normalize_preferences(incoming_preferences))

        put_change(changeset, :preferences, merged_preferences)

      _other ->
        add_error(changeset, :preferences, "must be a map")
    end
  end

  defp normalize_preferences(nil), do: %{}

  defp normalize_preferences(preferences) when is_map(preferences) do
    Map.new(preferences, fn {key, value} -> {to_string(key), value} end)
  end

  defp validate_timezone(changeset) do
    validate_change(changeset, :timezone, fn :timezone, timezone ->
      if is_binary(timezone) and Timex.Timezone.exists?(timezone) do
        []
      else
        [timezone: "must be a valid IANA timezone"]
      end
    end)
  end

  defp validate_time_format(changeset) do
    preferences = get_field(changeset, :preferences) || %{}

    case Map.get(preferences, "time_format") do
      nil -> changeset
      time_format when time_format in ["12h", "24h"] -> changeset
      _invalid -> add_error(changeset, :preferences, "time_format must be 12h or 24h")
    end
  end

  defp validate_theme(changeset) do
    valid_theme_ids = Enum.map(Foglet.TUI.Theme.ids(), &Atom.to_string/1)

    validate_change(changeset, :theme, fn :theme, theme ->
      if theme in valid_theme_ids do
        []
      else
        [theme: "is not a registered theme"]
      end
    end)
  end

  defp normalize_handle_color(changeset) do
    update_change(changeset, :handle_color, fn
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: value

      value ->
        value
    end)
  end

  defp validate_handle_color(changeset) do
    validate_change(changeset, :handle_color, fn :handle_color, handle_color ->
      cond do
        is_nil(handle_color) -> []
        is_binary(handle_color) and Regex.match?(@handle_color_format, handle_color) -> []
        true -> [handle_color: "must be a #RRGGBB hex color"]
      end
    end)
  end
end
