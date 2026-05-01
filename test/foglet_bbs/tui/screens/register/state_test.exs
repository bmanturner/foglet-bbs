defmodule Foglet.TUI.Screens.Register.StateTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.User
  alias Foglet.TUI.Screens.Register.State, as: RegisterState

  @generic_error "Please double-check the form and try again."

  describe "changeset_error_text/1 — FOG-53 §3.6a mapped shapes" do
    test "missing handle/email/password surfaces only the first failure (handle blank)" do
      cs = User.registration_changeset(%{})

      assert RegisterState.changeset_error_text(cs) == "Pick a handle."
    end

    test "missing email (handle + password present) maps to the email blank sentence" do
      cs =
        User.registration_changeset(%{handle: "okhandle", password: "sekret01"})

      assert RegisterState.changeset_error_text(cs) == "Enter an email address."
    end

    test "missing password (handle + email present) maps to the password blank sentence" do
      cs =
        User.registration_changeset(%{handle: "okhandle", email: "ok@example.test"})

      assert RegisterState.changeset_error_text(cs) == "Pick a password."
    end

    test "handle too long maps to the max-length sentence with the configured limit" do
      cs =
        User.registration_changeset(%{
          handle: String.duplicate("a", 21),
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Handles can't be longer than 20 characters."
    end

    test "handle with disallowed characters maps to the format sentence" do
      cs =
        User.registration_changeset(%{
          handle: "has.dot",
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Handles can only use letters, numbers, dashes, and underscores."
    end

    test "malformed email maps to the email format sentence" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "not-an-email",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "That doesn't look like an email address."
    end

    test "short password maps to the min-length sentence with the configured floor" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "ok@example.test",
          password: "short"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Passwords need to be at least 8 characters."
    end

    test "duplicate handle maps to the unique-handle sentence" do
      _existing = FogletBbs.AccountsFixtures.user_fixture(%{handle: "dupehandle"})

      cs =
        User.registration_changeset(%{
          handle: "dupehandle",
          email: "fresh@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "That handle is already in use. Pick another."
    end

    test "duplicate email maps to the unique-email sentence" do
      _existing = FogletBbs.AccountsFixtures.user_fixture(%{email: "dupe@example.test"})

      cs =
        User.registration_changeset(%{
          handle: "freshhandle",
          email: "dupe@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "That email is already on file."
    end

    test "handle below minimum length maps to the min-length sentence with the configured floor" do
      cs =
        User.registration_changeset(%{
          handle: "a",
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Handles need to be at least 2 characters."
    end

    test "oversize email maps to the max-length sentence with the configured limit" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: String.duplicate("a", 250) <> "@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Emails can't be longer than 254 characters."
    end

    test "oversize password maps to the max-length sentence with the configured limit" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "ok@example.test",
          password: String.duplicate("a", 257)
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Passwords can't be longer than 256 characters."
    end
  end

  describe "changeset_error_text/1 — unknown shapes fall back safely" do
    test "errors with no recognized validation/constraint metadata return the generic sentence" do
      cs =
        %User{}
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.add_error(:something_else, "is weird", custom: :metadata)

      text = RegisterState.changeset_error_text(cs)

      assert text == @generic_error
      refute text =~ "something_else"
      refute text =~ "is weird"
    end

    test "an empty error list still returns a friendly sentence" do
      cs = Ecto.Changeset.change(%User{}, %{})

      assert RegisterState.changeset_error_text(cs) == @generic_error
    end
  end
end
