defmodule Foglet.Mailer do
  @moduledoc """
  Swoosh mailer boundary for Foglet transactional delivery.

  Privacy-safe logging rule: delivery boundary logs must help operators identify
  the failed mail type, delivery mode, internal user ids, and sanitized provider
  reason without logging raw verification codes, reset tokens, invite codes,
  passwords, full email payloads, email addresses, handles, or other user-entered
  private data. Callers should keep user-facing responses generic where account
  enumeration or recovery-token disclosure is a risk.
  """

  require Logger

  use Swoosh.Mailer, otp_app: :foglet_bbs

  @doc """
  Delivers a transactional email and logs provider failures with safe context.

  Expected options:
    * `:mail_type` - low-cardinality atom/string for the transactional email.
    * `:recipient_user_id` - internal recipient user id, when known.
    * `:related_user_id` - optional internal secondary user id, when relevant.

  Raw email structs and user PII are intentionally not logged.
  """
  @spec deliver_transactional(Swoosh.Email.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def deliver_transactional(%Swoosh.Email{} = email, opts) when is_list(opts) do
    case deliver(email) do
      {:ok, _delivery} = ok ->
        ok

      {:error, reason} = error ->
        log_transactional_delivery_failure(reason, opts)
        error
    end
  end

  defp log_transactional_delivery_failure(reason, opts) do
    Logger.error(
      [
        "transactional_email_delivery_failed",
        "mail_type=#{safe_value(Keyword.fetch!(opts, :mail_type))}",
        "delivery_mode=#{Foglet.Config.delivery_mode()}",
        "recipient_user_id=#{safe_value(Keyword.get(opts, :recipient_user_id))}",
        related_user_fragment(Keyword.get(opts, :related_user_id)),
        "reason=#{inspect(reason)}"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    )
  end

  defp related_user_fragment(nil), do: nil
  defp related_user_fragment(user_id), do: "related_user_id=#{safe_value(user_id)}"

  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_binary(value), do: value
  defp safe_value(value), do: inspect(value)
end
