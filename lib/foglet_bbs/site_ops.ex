defmodule Foglet.SiteOps do
  @moduledoc """
  Operator-scoped site actions that don't fit cleanly inside Accounts/Boards.

  Currently provides the "send test email" action for the SITE configuration
  screen. Authorization, delivery-mode, and missing-email guards live here so
  the TUI never decides whether a transactional send is allowed — the domain
  is the trust boundary.
  """

  require Logger

  alias Foglet.Accounts.{Email, User}
  alias Foglet.{Authorization, Config, Mailer}

  @typedoc """
  Result shape for `send_test_email/1`.

    * `{:ok, term()}` — Mailer accepted the email; payload is the adapter's
      delivery term, mirroring `Foglet.Mailer.deliver_transactional/2`.
    * `{:error, :forbidden}` — actor is not an authorized sysop.
    * `{:error, :no_email_mode}` — current `delivery_mode` is `"no_email"`;
      no delivery attempted.
    * `{:error, :missing_email}` — sysop has no account email; no delivery
      attempted.
    * `{:error, term()}` — provider/transport failure surfaced from the
      mailer; logged with privacy-safe test-email context.
  """
  @type send_test_email_result ::
          {:ok, term()}
          | {:error, :forbidden | :no_email_mode | :missing_email | term()}

  @doc """
  Send a Foglet test email to the acting sysop's own account email.

  The recipient is always the actor — there is no arbitrary-recipient
  parameter. The body contains no secrets (verification codes, reset tokens,
  invite codes, passwords, SSH key material).
  """
  @spec send_test_email(User.t() | nil) :: send_test_email_result()
  def send_test_email(actor) do
    with :ok <- Bodyguard.permit(Authorization, :send_test_email, actor, :site),
         :ok <- check_delivery_mode(),
         {:ok, sysop} <- check_recipient_email(actor) do
      deliver_test_email(sysop)
    end
  end

  defp deliver_test_email(%User{} = sysop) do
    Mailer.deliver_transactional(Email.test_email(sysop),
      mail_type: :sysop_test_email,
      recipient_user_id: sysop.id
    )
  rescue
    exception ->
      reason = {:delivery_exception, exception.__struct__}
      log_test_email_failure(reason, sysop)
      {:error, reason}
  catch
    kind, value ->
      reason = {:delivery_failed, kind, safe_reason_class(value)}
      log_test_email_failure(reason, sysop)
      {:error, reason}
  else
    {:ok, _delivery} = ok ->
      ok

    {:error, reason} = error ->
      log_test_email_failure(reason, sysop)
      error
  end

  defp log_test_email_failure(reason, %User{} = sysop) do
    Logger.error(
      [
        "sysop_test_email_delivery_failed",
        "operation=send_test_email",
        "mail_type=sysop_test_email",
        "delivery_mode=#{Config.delivery_mode()}",
        "recipient_user_id=#{safe_value(sysop.id)}",
        "reason=#{inspect(reason)}"
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    )
  end

  defp safe_reason_class(%module{}) when is_atom(module), do: module
  defp safe_reason_class(value) when is_atom(value), do: value
  defp safe_reason_class(value) when is_tuple(value), do: elem(value, 0)
  defp safe_reason_class(value) when is_binary(value), do: :binary
  defp safe_reason_class(_value), do: :unknown

  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_binary(value), do: value
  defp safe_value(value), do: inspect(value)

  defp check_delivery_mode do
    case Config.delivery_mode() do
      "email" -> :ok
      "no_email" -> {:error, :no_email_mode}
    end
  end

  defp check_recipient_email(%User{email: email} = sysop)
       when is_binary(email) and email != "" do
    {:ok, sysop}
  end

  defp check_recipient_email(%User{}), do: {:error, :missing_email}
end
