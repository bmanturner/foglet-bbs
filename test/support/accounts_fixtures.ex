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
    attrs =
      attrs
      |> valid_user_attributes()
      |> maybe_put_invite_code()

    {:ok, user} = Accounts.register_user(attrs)
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
        %{code: unique_invite_code()},
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

  defp maybe_put_invite_code(attrs) do
    if invite_code_present?(attrs) do
      attrs
    else
      case Foglet.Config.registration_mode() do
        "invite_only" -> Map.put(attrs, :invite_code, fixture_invite_code())
        _mode -> attrs
      end
    end
  end

  defp invite_code_present?(attrs) do
    Map.has_key?(attrs, :invite_code) or Map.has_key?(attrs, "invite_code")
  end

  defp fixture_invite_code do
    issuer_attrs =
      valid_user_attributes(%{
        handle: "inviteissuer#{System.unique_integer([:positive])}",
        email: "inviteissuer#{System.unique_integer([:positive])}@example.com"
      })

    issuer =
      %User{}
      |> User.registration_changeset(issuer_attrs)
      |> Ecto.Changeset.change(role: :sysop)
      |> Repo.insert!()

    invite_fixture(issuer).code
  end

  defp unique_invite_code do
    suffix =
      System.unique_integer([:positive])
      |> Integer.to_string(36)
      |> String.pad_leading(5, "0")
      |> String.slice(-5, 5)

    "F" <> suffix
  end
end
