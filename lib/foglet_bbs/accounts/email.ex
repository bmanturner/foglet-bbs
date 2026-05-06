defmodule Foglet.Accounts.Email do
  @moduledoc """
  Text-only transactional email builders for Accounts flows.
  """

  import Swoosh.Email

  alias Foglet.Accounts.User

  @default_from_address "no-reply@localhost"

  @doc "Build an email verification-code message."
  @spec verification_code(User.t(), String.t()) :: Swoosh.Email.t()
  def verification_code(%User{} = user, code) when is_binary(code) do
    app_name = Foglet.AppName.name()

    new()
    |> to({user.handle, user.email})
    |> from(from_mailbox())
    |> subject("Your #{app_name} verification code")
    |> text_body("""
    Your #{app_name} verification code is:

    #{code}

    Return to your SSH terminal session and enter this code on the verification screen.
    """)
  end

  @doc "Build terminal-native password reset instructions."
  @spec password_reset(User.t(), String.t()) :: Swoosh.Email.t()
  def password_reset(%User{} = user, reset_token) when is_binary(reset_token) do
    app_name = Foglet.AppName.name()

    new()
    |> to({user.handle, user.email})
    |> from(from_mailbox())
    |> subject("#{app_name} password reset instructions")
    |> text_body("""
    A password reset was requested for your #{app_name} account.

    Reset token:

    #{reset_token}

    Return to the SSH terminal reset flow and enter this token when prompted. If your instance uses an operator-assisted reset procedure, provide this token to the operator through that procedure.

    If you did not request this reset, ignore this message.
    """)
  end

  @doc "Build an account approval notification."
  @spec approval_notification(User.t()) :: Swoosh.Email.t()
  def approval_notification(%User{} = user) do
    app_name = Foglet.AppName.name()

    new()
    |> to({user.handle, user.email})
    |> from(from_mailbox())
    |> subject("Your #{app_name} account was approved")
    |> text_body("""
    Your #{app_name} account was approved.

    You can now return to your SSH terminal and log in.
    """)
  end

  @doc "Build a registration rejection notification."
  @spec rejection_notification(User.t()) :: Swoosh.Email.t()
  def rejection_notification(%User{} = user) do
    app_name = Foglet.AppName.name()

    new()
    |> to({user.handle, user.email})
    |> from(from_mailbox())
    |> subject("Your #{app_name} registration was rejected")
    |> text_body("""
    Your #{app_name} registration was rejected.

    Contact the sysop if you believe this was a mistake.
    """)
  end

  @doc """
  Build the operator-initiated test email.

  Sent to the acting sysop's own account email address. The body contains no
  verification codes, reset tokens, invite codes, passwords, SSH key material,
  or other secrets — it is purely a delivery sanity check.
  """
  @spec test_email(User.t()) :: Swoosh.Email.t()
  def test_email(%User{} = sysop) do
    app_name = Foglet.AppName.name()

    new()
    |> to({sysop.handle, sysop.email})
    |> from(from_mailbox())
    |> subject("#{app_name} test email")
    |> text_body("""
    This is a #{app_name} test email.

    A sysop triggered this delivery from the SITE configuration screen to
    confirm that transactional email is reaching this address. No action is
    required.

    If you did not request this test, you can ignore this message.
    """)
  end

  @doc "Build a sysop notification for a pending registration."
  @spec pending_approval_notification(User.t(), User.t()) :: Swoosh.Email.t()
  def pending_approval_notification(%User{} = sysop, %User{} = pending_user) do
    app_name = Foglet.AppName.name()

    new()
    |> to({sysop.handle, sysop.email})
    |> from(from_mailbox())
    |> subject("#{app_name} account awaiting approval")
    |> text_body("""
    A new #{app_name} account is awaiting sysop approval.

    Handle: #{pending_user.handle}
    Email: #{pending_user.email}

    Return to the SSH terminal Sysop USERS tab to approve or reject this account.
    """)
  end

  defp from_mailbox do
    {Foglet.AppName.name(), Application.get_env(:foglet_bbs, :mail_from, @default_from_address)}
  end
end
