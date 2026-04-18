defmodule Foglet.Accounts.SSHKey do
  @moduledoc """
  SSH public key registered to a user. Auth logic lives in Phase 3;
  Phase 1 is schema + storage only.

  See `docs/DATA_MODEL.md` §1.
  """

  use Foglet.Schema

  @type t :: %__MODULE__{}

  schema "ssh_keys" do
    field :label, :string
    field :public_key, :string
    field :fingerprint, :string
    field :last_used_at, :utc_datetime_usec

    belongs_to :user, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @label_min 1
  @label_max 64

  @doc """
  Changeset for registering a new SSH key.

  Computes the SHA256 fingerprint from the OpenSSH-formatted public_key.
  Adds a changeset error on :public_key if the key cannot be decoded.

  Note: `user_id` is set explicitly on the struct (not cast) — programmatic
  fields per CLAUDE.md.
  """
  def changeset(ssh_key, attrs) do
    ssh_key
    |> cast(attrs, [:label, :public_key])
    |> validate_required([:label, :public_key])
    |> validate_length(:label, min: @label_min, max: @label_max)
    |> put_fingerprint()
    |> unique_constraint(:fingerprint)
    |> unique_constraint([:user_id, :label], name: :ssh_keys_user_id_label_index)
  end

  @doc """
  Compute a stable SHA256 fingerprint from an OpenSSH-formatted public key.

  Uses OTP's :ssh_file.decode/2 to parse the OpenSSH wire format, then
  :public_key.ssh_hostkey_fingerprint/2 to generate the fingerprint.
  Returns a string like "SHA256:<base64>" to match the OpenSSH convention.
  """
  def compute_fingerprint(public_key_text) when is_binary(public_key_text) do
    trimmed = String.trim(public_key_text)

    case decode_ssh_key(trimmed) do
      {:ok, key} ->
        fp = :ssh.hostkey_fingerprint(:sha256, key)
        {:ok, to_string(fp)}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    _ -> {:error, "invalid OpenSSH public key"}
  end

  # ---------- Private ----------

  defp put_fingerprint(changeset) do
    case get_change(changeset, :public_key) do
      nil ->
        changeset

      public_key ->
        case compute_fingerprint(public_key) do
          {:ok, fp} -> put_change(changeset, :fingerprint, fp)
          {:error, reason} -> add_error(changeset, :public_key, reason)
        end
    end
  end

  defp decode_ssh_key(text) do
    case :ssh_file.decode(text, :public_key) do
      [{key, _comments} | _] ->
        {:ok, key}

      [] ->
        {:error, "invalid OpenSSH public key: empty"}

      {:error, reason} ->
        {:error, "invalid OpenSSH public key: #{inspect(reason)}"}
    end
  end
end
