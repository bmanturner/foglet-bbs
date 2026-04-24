defmodule Foglet.Accounts.Email do
  @moduledoc """
  Text-only transactional email builders for Accounts flows.
  """

  import Swoosh.Email

  alias Foglet.Accounts.User

  @from {"Foglet BBS", "no-reply@localhost"}

  @doc "Build an email verification-code message."
  @spec verification_code(User.t(), String.t()) :: Swoosh.Email.t()
  def verification_code(%User{} = user, code) when is_binary(code) do
    new()
    |> to({user.handle, user.email})
    |> from(@from)
    |> subject("Your Foglet verification code")
    |> text_body("""
    Your Foglet verification code is:

    #{code}

    Return to your SSH terminal session and enter this code on the verification screen.
    """)
  end

  @doc "Build terminal-native password reset instructions."
  @spec password_reset(User.t(), String.t()) :: Swoosh.Email.t()
  def password_reset(%User{} = user, reset_token) when is_binary(reset_token) do
    new()
    |> to({user.handle, user.email})
    |> from(@from)
    |> subject("Foglet password reset instructions")
    |> text_body("""
    A password reset was requested for your Foglet account.

    Reset token:

    #{reset_token}

    Return to the SSH terminal reset flow and enter this token when prompted. If your instance uses an operator-assisted reset procedure, provide this token to the operator through that procedure.

    If you did not request this reset, ignore this message.
    """)
  end

  @doc "Build an account approval notification."
  @spec approval_notification(User.t()) :: Swoosh.Email.t()
  def approval_notification(%User{} = user) do
    new()
    |> to({user.handle, user.email})
    |> from(@from)
    |> subject("Your Foglet account was approved")
    |> text_body("""
    Your Foglet account was approved.

    You can now return to your SSH terminal and log in.
    """)
  end

  @doc "Build a registration rejection notification."
  @spec rejection_notification(User.t()) :: Swoosh.Email.t()
  def rejection_notification(%User{} = user) do
    new()
    |> to({user.handle, user.email})
    |> from(@from)
    |> subject("Your Foglet registration was rejected")
    |> text_body("""
    Your Foglet registration was rejected.

    Contact the sysop if you believe this was a mistake.
    """)
  end
end
