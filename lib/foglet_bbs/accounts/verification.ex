defmodule Foglet.Accounts.Verification do
  @moduledoc """
  Email-verification and password-reset functions for `Foglet.Accounts`.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.{Email, User, UserToken}
  alias Foglet.QueryHelpers
  alias FogletBbs.Repo

  # D-02: simple local email shape — non-empty local-part, single `@`,
  # non-empty domain with at least one dot and non-empty domain segments.
  # Intentionally not RFC-complete; mirrors `User`'s registration regex.
  #
  # WR-001: this is the single source of truth for the local email-shape
  # gate. Callers (e.g. `Foglet.TUI.Screens.Login`) MUST use
  # `email_shape?/1` rather than re-declaring the regex; loosening one copy
  # without the other previously risked the screen and the boundary
  # silently disagreeing on what counts as a valid email.
  @email_shape_regex ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/

  @doc """
  Predicate for the local email-shape gate (D-02).

  Returns true when `value` is a binary that matches the shared
  `@email_shape_regex`. Used by `request_password_reset_delivery/1`
  internally and by the Login screen for inline pre-submit validation.
  """
  @spec email_shape?(term()) :: boolean()
  def email_shape?(value) when is_binary(value),
    do: Regex.match?(@email_shape_regex, value)

  def email_shape?(_other), do: false

  @doc """
  Build and persist an email verification code for `user`. Returns the raw 6-char
  alphanumeric code (the value to show/email/log to the user). The code expires in
  15 minutes. See D-08, D-10.
  """
  @spec build_verify_code(User.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def build_verify_code(%User{} = user) do
    {raw_code, token_struct} = UserToken.build_verify_code(user)

    case Repo.insert(token_struct) do
      {:ok, _} -> {:ok, raw_code}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc """
  Persist and attempt delivery of an email verification code.

  Delivery is available only when `Foglet.Config.delivery_mode/0` is `"email"`.
  Provider-specific errors are intentionally collapsed so TUI callers can keep
  user-facing copy generic.
  """
  @spec deliver_verification_code(User.t()) ::
          {:ok, :attempted} | {:error, :unavailable | :delivery_failed | Ecto.Changeset.t()}
  def deliver_verification_code(%User{} = user) do
    case Foglet.Config.delivery_mode() do
      "email" ->
        with {:ok, code} <- build_verify_code(user),
             {:ok, _delivery} <- Foglet.Mailer.deliver(Email.verification_code(user, code)) do
          {:ok, :attempted}
        else
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          {:error, _reason} -> {:error, :delivery_failed}
        end

      "no_email" ->
        {:error, :unavailable}
    end
  end

  @doc """
  Verify an email code for `user`. On success, confirms the user (sets `confirmed_at`)
  and returns `{:ok, confirmed_user}`. On failure returns:
    - `{:error, :invalid_code}` — code did not match any non-expired verify token
    - `{:error, :expired}` — token exists but inserted_at > 15 minutes ago
  See D-10, D-12.
  """
  @spec verify_email_code(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_code | :expired}
  def verify_email_code(%User{email: email} = user, code)
      when is_binary(code) and byte_size(code) > 0 do
    valid_row =
      code
      |> UserToken.verify_code_query(email)
      |> Repo.one()

    cond do
      valid_row != nil and valid_row.user_id == user.id ->
        Repo.transact(fn ->
          with {:ok, confirmed} <- user |> User.confirm_changeset() |> Repo.update() do
            Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["email_verify"]))
            {:ok, confirmed}
          end
        end)

      expired_exists?(user, code) ->
        {:error, :expired}

      true ->
        {:error, :invalid_code}
    end
  end

  @doc """
  Request terminal-native password reset delivery for a handle or email.

  In email delivery mode this function is enumeration-safe: active matches,
  unknown identifiers, deleted accounts, inactive accounts, and provider
  failures all return the same outward result.
  """
  @spec request_password_reset_delivery(String.t()) ::
          {:ok, :generic_response} | {:error, :unavailable}
  def request_password_reset_delivery(identifier) when is_binary(identifier) do
    case Foglet.Config.delivery_mode() do
      "no_email" ->
        {:error, :unavailable}

      "email" ->
        identifier
        |> String.trim()
        |> find_reset_delivery_user()
        |> maybe_deliver_password_reset()

        {:ok, :generic_response}
    end
  end

  @doc """
  Reset a user's password. After update, deletes any outstanding
  reset_password tokens for that user so a used token can't be replayed.
  """
  @spec reset_user_password(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
        Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
        {:ok, updated}
      end
    end)
  end

  @doc """
  Build and persist a reset-password token for operator-assisted retrieval.

  Returns the raw token once so the caller can hand it to the user through a
  supported operator-controlled channel. Only the hashed token row is stored.
  """
  @spec generate_reset_token_for_operator(User.t()) ::
          {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def generate_reset_token_for_operator(%User{} = user) do
    {raw_token, token_struct} = UserToken.build_email_token(user, "reset_password")

    case Repo.insert(token_struct) do
      {:ok, _token} -> {:ok, raw_token}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @doc """
  Atomically consume a raw reset-password token to update a user's password.

  Verifies the raw token, applies `User.password_changeset/2`, deletes the
  consumed token row, and removes any other outstanding `reset_password`
  tokens for that user. The verify-claim-update-cleanup sequence runs inside
  a single `Repo.transact/1` so concurrent consumers of the same raw token
  race on the row-claim delete and exactly one observes `{1, _}` (D-08, D-09,
  D-10, D-16).

  Returns:
    * `{:ok, %User{}}` on success.
    * `{:error, :invalid_or_expired}` for an unknown, malformed, expired, or
      already-consumed raw token.
    * `{:error, %Ecto.Changeset{}}` when the new password fails validation;
      no token is consumed and no password is changed.

  Generic invalid/expired errors do not leak whether a token existed or
  whether an associated account exists (D-10).
  """
  @spec consume_reset_token(String.t(), map()) ::
          {:ok, User.t()} | {:error, :invalid_or_expired | Ecto.Changeset.t()}
  def consume_reset_token(raw_token, attrs) when is_binary(raw_token) and is_map(attrs) do
    with {:ok, user_query} <- UserToken.verify_email_token_query(raw_token, "reset_password"),
         {:ok, claim_query} <- UserToken.reset_token_claim_query(raw_token) do
      Repo.transact(fn ->
        case Repo.one(user_query) do
          nil ->
            {:error, :invalid_or_expired}

          %User{} = user ->
            # Atomic single-use claim: PostgreSQL row locking ensures exactly
            # one concurrent transaction observes {1, _}; the rest see {0, _}
            # and short-circuit to a generic invalid_or_expired error.
            case Repo.delete_all(claim_query) do
              {0, _} -> {:error, :invalid_or_expired}
              {_n, _} -> update_password_and_purge_resets(user, attrs)
            end
        end
      end)
    else
      :error -> {:error, :invalid_or_expired}
    end
  end

  defp update_password_and_purge_resets(user, attrs) do
    with {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
      # Defense in depth: drop any other outstanding reset tokens for this
      # user so nothing left over can be replayed.
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
      {:ok, updated}
    end
  end

  @doc """
  Return active, non-deleted sysop contact emails (D-13/D-14).

  Used by the Login screen's no-email reset copy to list operator-assisted
  reset contacts. The list excludes deleted, pending, suspended, rejected,
  non-sysop, and nil-email users. Results are sorted by email so the rendered
  comma-separated list is deterministic between requests and inside tests.
  """
  @spec active_sysop_contact_emails() :: [String.t()]
  def active_sysop_contact_emails do
    from(u in User,
      where: u.role == :sysop and u.status == :active and not is_nil(u.email),
      order_by: [asc: u.email],
      select: u.email
    )
    |> QueryHelpers.not_deleted()
    |> Repo.all()
  end

  defp expired_exists?(%User{id: user_id, email: email}, code) do
    validity = UserToken.email_verify_validity_minutes()

    query =
      from t in UserToken,
        where:
          t.token == ^code and t.context == "email_verify" and
            t.sent_to == ^email and t.user_id == ^user_id and
            t.inserted_at <= ago(^validity, "minute")

    Repo.exists?(query)
  end

  defp find_reset_delivery_user(""), do: nil

  defp find_reset_delivery_user(identifier) do
    # D-02/D-13/D-16: email-only lookup. Handle-shaped identifiers no longer
    # produce token side effects; only valid email-shaped input that matches
    # an active, non-deleted account creates a reset token.
    if email_shape?(identifier) do
      case Repo.get_by(User, email: identifier) do
        %User{status: :active, deleted_at: nil} = user -> user
        _other -> nil
      end
    else
      nil
    end
  end

  defp maybe_deliver_password_reset(nil), do: :ok

  defp maybe_deliver_password_reset(%User{} = user) do
    {raw_token, token_struct} = UserToken.build_email_token(user, "reset_password")

    with {:ok, _token} <- Repo.insert(token_struct) do
      _ = Foglet.Mailer.deliver(Email.password_reset(user, raw_token))
      :ok
    end
  end
end
