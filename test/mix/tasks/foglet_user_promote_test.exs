defmodule Mix.Tasks.Foglet.User.PromoteTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.Accounts
  alias FogletBbs.AccountsFixtures

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.user.promote (IDNT-06)" do
    test "promotes an existing user to sysop given handle + --role sysop" do
      user = AccountsFixtures.user_fixture(%{handle: "promoteme"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Promote.run(["promoteme", "--role", "sysop"])
        end)

      assert output =~ "Promoted promoteme to sysop"

      reloaded = Accounts.get_user_by_handle("promoteme")
      assert reloaded.id == user.id
      assert reloaded.role == :sysop
    end

    test "accepts role 'user'" do
      _ = AccountsFixtures.user_fixture(%{handle: "u1"})

      capture_io(fn ->
        Mix.Tasks.Foglet.User.Promote.run(["u1", "--role", "user"])
      end)

      assert Accounts.get_user_by_handle("u1").role == :user
    end

    test "accepts role 'mod'" do
      _ = AccountsFixtures.user_fixture(%{handle: "u2"})

      capture_io(fn ->
        Mix.Tasks.Foglet.User.Promote.run(["u2", "--role", "mod"])
      end)

      assert Accounts.get_user_by_handle("u2").role == :mod
    end

    test "rejects invalid role string with non-zero exit and no atom leak" do
      _ = AccountsFixtures.user_fixture(%{handle: "u3"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.Promote.run(["u3", "--role", "admin"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Invalid role"

      # Confirm :admin was never converted to an atom via String.to_atom/1.
      # The valid_roles list only contains :user, :mod, :sysop.
      assert Foglet.Accounts.User.valid_roles() == [:user, :mod, :sysop]
    end

    test "unknown handle exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.Promote.run(["no_such_user", "--role", "mod"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "User not found"
    end

    test "missing handle exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.Promote.run(["--role", "mod"])) == {:shutdown, 1}
      end)
    end

    test "missing --role exits non-zero" do
      _ = AccountsFixtures.user_fixture(%{handle: "norole"})

      capture_io(:stderr, fn ->
        assert catch_exit(Mix.Tasks.Foglet.User.Promote.run(["norole"])) == {:shutdown, 1}
      end)
    end

    test "unknown flag exits non-zero" do
      _ = AccountsFixtures.user_fixture(%{handle: "unknownflag"})

      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.User.Promote.run([
                   "unknownflag",
                   "--role",
                   "mod",
                   "--bogus",
                   "x"
                 ])
               ) == {:shutdown, 1}
      end)
    end
  end
end
