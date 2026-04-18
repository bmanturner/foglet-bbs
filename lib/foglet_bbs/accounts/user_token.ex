defmodule Foglet.Accounts.UserToken do
  @moduledoc """
  Email confirmation, password reset, and CLI session tokens.

  Follows the phx.gen.auth pattern: generate 32 random bytes, store the
  SHA256 hash, return the raw token base64url-encoded. The raw token
  cannot be reconstructed from the database.

  Contexts: "confirm" (7-day expiry), "reset_password" (1-day expiry),
  "cli_session" (longer-lived; wired in Phase 13).

  See `docs/DATA_MODEL.md` §1 and research Pattern 2.
  """

  use Foglet.Schema

  import Ecto.Query

  @type t :: %__MODULE__{}

  @hash_algorithm :sha256
  @rand_size 32

  @confirm_validity_in_days 7
  @reset_password_validity_in_days 1
  @cli_session_validity_in_days 60

  @email_verify_validity_in_minutes 15
  @verify_code_length 6

  schema "user_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string

    belongs_to :user, Foglet.Accounts.User

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc """
  Build a token for the given user and context.

  Returns `{raw_token, %UserToken{}}`. The raw token (base64url-encoded)
  is what you send to the user; the struct (with the SHA256 hash in
  `:token`) is what you persist.
  """
  @spec build_email_token(Foglet.Accounts.User.t(), String.t()) :: {String.t(), t()}
  def build_email_token(user, context) when context in ["confirm", "reset_password"] do
    build_hashed_token(user, context, user.email)
  end

  @doc """
  Build a CLI session token (Phase 13). Same pattern, longer expiry.
  """
  @spec build_cli_session_token(Foglet.Accounts.User.t()) :: {String.t(), t()}
  def build_cli_session_token(user) do
    build_hashed_token(user, "cli_session", nil)
  end

  @doc """
  Build an email verification code (D-08). Generates a 6-char uppercase alphanumeric
  code, returns `{raw_code, %UserToken{}}`. The code is stored in the `:token` field
  as a UTF-8 binary (NOT hashed — short-lived codes per D-10 don't need hashing).

  See Pitfall 6: do NOT reuse build_email_token/2 for verify codes.
  """
  @spec build_verify_code(Foglet.Accounts.User.t()) :: {String.t(), t()}
  def build_verify_code(%{id: user_id, email: email}) do
    raw_code = generate_verify_code()

    {raw_code,
     %__MODULE__{
       token: raw_code,
       context: "email_verify",
       sent_to: email,
       user_id: user_id
     }}
  end

  @doc """
  Query matching a verify code for a user. Returns rows where:
    - token == ^code (plain match, not hashed)
    - context == "email_verify"
    - inserted_at > ago(15, "minute")
    - sent_to == ^user_email
  """
  @spec verify_code_query(String.t(), String.t()) :: Ecto.Query.t()
  def verify_code_query(code, user_email) when is_binary(code) and is_binary(user_email) do
    from t in __MODULE__,
      where:
        t.token == ^code and t.context == "email_verify" and
          t.sent_to == ^user_email and
          t.inserted_at > ago(^@email_verify_validity_in_minutes, "minute")
  end

  @doc "Validity window for email verify codes (minutes). Used by tests."
  def email_verify_validity_minutes, do: @email_verify_validity_in_minutes

  @doc "Length of verify codes. Used by tests."
  def verify_code_length, do: @verify_code_length

  @doc """
  Build a query to verify a raw token and fetch the associated user.

  Returns `{:ok, query}` or `:error`. The returned query yields the user
  row only if:
    - the decoded token hashes to a stored row in the given context
    - the token was inserted within the per-context expiry window
    - for "confirm"/"reset_password", `sent_to == user.email` (so the user
      changing their email invalidates outstanding tokens)
  """
  @spec verify_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_email_token_query(token, context)
      when context in ["confirm", "reset_password"] do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} ->
        hashed = :crypto.hash(@hash_algorithm, decoded)
        days = days_for_context(context)

        query =
          from t in by_token_and_context_query(hashed, context),
            join: u in assoc(t, :user),
            where: t.inserted_at > ago(^days, "day") and t.sent_to == u.email,
            select: u

        {:ok, query}

      :error ->
        :error
    end
  end

  @doc "Query token rows by raw-hashed-token value and context."
  def by_token_and_context_query(hashed_token, context) do
    from t in __MODULE__, where: t.token == ^hashed_token and t.context == ^context
  end

  @doc "Query all tokens for a user (used by delete_user/1)."
  def by_user_and_contexts_query(user, :all) do
    from t in __MODULE__, where: t.user_id == ^user.id
  end

  def by_user_and_contexts_query(user, contexts) when is_list(contexts) do
    from t in __MODULE__, where: t.user_id == ^user.id and t.context in ^contexts
  end

  @doc "Public accessor for validity periods (used by tests and Plan 03)."
  def validity_days("confirm"), do: @confirm_validity_in_days
  def validity_days("reset_password"), do: @reset_password_validity_in_days
  def validity_days("cli_session"), do: @cli_session_validity_in_days

  @doc "Hash algorithm accessor for tests."
  def hash_algorithm, do: @hash_algorithm

  @doc "Random bytes size accessor for tests."
  def rand_size, do: @rand_size

  # ---------- Private ----------

  defp generate_verify_code do
    :crypto.strong_rand_bytes(@verify_code_length)
    |> Base.encode32(padding: false)
    |> binary_part(0, @verify_code_length)
    |> String.upcase()
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %__MODULE__{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  defp days_for_context("confirm"), do: @confirm_validity_in_days
  defp days_for_context("reset_password"), do: @reset_password_validity_in_days
  defp days_for_context("cli_session"), do: @cli_session_validity_in_days
end
