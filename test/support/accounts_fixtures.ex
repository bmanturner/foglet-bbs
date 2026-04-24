defmodule FogletBbs.AccountsFixtures do
  @moduledoc """
  Fixtures for account-related tests.
  """

  alias Foglet.Accounts
  alias Foglet.Accounts.{Invite, User, UserToken}
  alias FogletBbs.Repo

  @doc "Valid attrs for registration — override any key in the overrides map."
  def valid_user_attributes(overrides \\ %{}) do
    Map.merge(
      %{
        handle: "user#{System.unique_integer([:positive])}",
        email: "user#{System.unique_integer([:positive])}@example.com",
        password: "correct horse battery"
      },
      overrides
    )
  end

  @doc "Insert a user via Foglet.Accounts.register_user/1."
  def user_fixture(attrs \\ %{}) do
    {:ok, user} = attrs |> valid_user_attributes() |> Accounts.register_user()
    user
  end

  @doc "Insert an invite, optionally for a specific issuer user."
  def invite_fixture(arg \\ %{})

  def invite_fixture(%User{} = issuer), do: invite_fixture(issuer, %{})

  def invite_fixture(attrs) when is_map(attrs) and not is_struct(attrs) do
    invite_fixture(user_fixture(), attrs)
  end

  def invite_fixture(%User{} = issuer, attrs) do
    attrs =
      Map.merge(
        %{code: "INVITECODE#{System.unique_integer([:positive])}XYZCODE"},
        attrs
      )

    %Invite{issuer_id: issuer.id}
    |> Invite.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  An Ed25519 public key used as the default for ssh_key_fixture. Callers
  can pass a different `:public_key` in overrides to get a distinct fingerprint.
  """
  @default_ssh_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGk+NU3dUxm5p8e2fMAKw1Z0p+4rM7q2DnGkgpTsvc0A test@example"

  def default_ssh_public_key, do: @default_ssh_key

  @doc "Insert an SSH key for the given user."
  def ssh_key_fixture(%User{} = user, attrs \\ %{}) do
    params =
      Map.merge(
        %{label: "key#{System.unique_integer([:positive])}", public_key: @default_ssh_key},
        attrs
      )

    {:ok, key} = Accounts.register_ssh_key(user, params)
    key
  end

  @doc "Build and insert an email token (confirm or reset_password)."
  def user_token_fixture(%User{} = user, context)
      when context in ["confirm", "reset_password"] do
    {raw, struct} = UserToken.build_email_token(user, context)
    {:ok, inserted} = FogletBbs.Repo.insert(struct)
    {raw, inserted}
  end
end
