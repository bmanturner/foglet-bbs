defmodule FogletBbs.AccountsFixtures do
  @moduledoc """
  Fixtures for account-related tests.

  Implementation is filled in by Plan 02 (schemas) and Plan 03 (context).
  Plan 01 creates only the module skeleton so downstream test files
  can reference it without ImportError.
  """

  @doc "Valid attrs for registration — override any key in the overrides map."
  def valid_user_attributes(overrides \\ %{}) do
    Map.merge(
      %{
        handle: "user_#{System.unique_integer([:positive])}",
        email: "user_#{System.unique_integer([:positive])}@example.com",
        password: "correct horse battery staple"
      },
      overrides
    )
  end

  @doc "Insert a user. Raises until Plan 03 fills in the context API."
  def user_fixture(_attrs \\ %{}) do
    raise "user_fixture/1 not implemented until Plan 03 wires Foglet.Accounts.register_user/1"
  end

  @doc "Insert an SSH key. Raises until Plan 03 fills in the context API."
  def ssh_key_fixture(_user, _attrs \\ %{}) do
    raise "ssh_key_fixture/2 not implemented until Plan 03 wires Foglet.Accounts.register_ssh_key/2"
  end

  @doc "Build an unsaved user token. Raises until Plan 02 exposes UserToken.build_email_token/2."
  def user_token_fixture(_user, _context) do
    raise "user_token_fixture/2 not implemented until Plan 02 defines Foglet.Accounts.UserToken"
  end
end
