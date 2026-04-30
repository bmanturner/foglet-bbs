defmodule Foglet.TUI.Screens.Register.StateTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.User
  alias Foglet.TUI.Screens.Register.State, as: RegisterState

  describe "changeset_error_text/1 — known User registration shapes" do
    test "missing handle, email, and password each produce a friendly required sentence" do
      cs = User.registration_changeset(%{})
      text = RegisterState.changeset_error_text(cs)

      assert text =~ "Please choose a handle."
      assert text =~ "Please enter an email address."
      assert text =~ "Please choose a password."
    end

    test "handle too short reports the allowed handle range" do
      cs =
        User.registration_changeset(%{
          handle: "a",
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "Handle must be 2–20 characters."
    end

    test "handle too long reports the allowed handle range" do
      cs =
        User.registration_changeset(%{
          handle: String.duplicate("a", 21),
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "Handle must be 2–20 characters."
    end

    test "handle with disallowed characters reports the format rule" do
      cs =
        User.registration_changeset(%{
          handle: "bad handle!",
          email: "ok@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Handle can only contain letters, numbers, underscores, and hyphens."
    end

    test "malformed email reports a generic email format sentence" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "not-an-email",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "Please enter a valid email address."
    end

    test "oversize email reports a length sentence" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: String.duplicate("a", 250) <> "@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) =~ "email address is too long"
    end

    test "short password reports the minimum length" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "ok@example.test",
          password: "short"
        })

      assert RegisterState.changeset_error_text(cs) ==
               "Password must be at least 8 characters."
    end

    test "long password reports the too-long sentence" do
      cs =
        User.registration_changeset(%{
          handle: "okhandle",
          email: "ok@example.test",
          password: String.duplicate("a", 257)
        })

      assert RegisterState.changeset_error_text(cs) == "Password is too long."
    end

    test "duplicate handle reports the unique sentence" do
      _existing = FogletBbs.AccountsFixtures.user_fixture(%{handle: "dupehandle"})

      cs =
        User.registration_changeset(%{
          handle: "dupehandle",
          email: "fresh@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "That handle is already taken."
    end

    test "duplicate email reports the unique sentence" do
      _existing = FogletBbs.AccountsFixtures.user_fixture(%{email: "dupe@example.test"})

      cs =
        User.registration_changeset(%{
          handle: "freshhandle",
          email: "dupe@example.test",
          password: "sekret01"
        })

      assert RegisterState.changeset_error_text(cs) == "That email is already in use."
    end
  end

  describe "changeset_error_text/1 — unknown shapes fall back safely" do
    test "errors with no recognized validation/constraint metadata return the generic sentence" do
      cs =
        %User{}
        |> Ecto.Changeset.change(%{})
        |> Ecto.Changeset.add_error(:something_else, "is weird", custom: :metadata)

      text = RegisterState.changeset_error_text(cs)

      assert text == "Please double-check the form and try again."
      refute text =~ "something_else"
      refute text =~ "is weird"
    end

    test "an empty error list still returns a friendly sentence" do
      cs = Ecto.Changeset.change(%User{}, %{})

      assert RegisterState.changeset_error_text(cs) ==
               "Please double-check the form and try again."
    end
  end
end
