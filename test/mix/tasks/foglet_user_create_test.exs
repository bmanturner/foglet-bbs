defmodule Mix.Tasks.Foglet.User.CreateTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.Accounts
  alias Foglet.Accounts.User

  setup do
    # Capture Mix shell output as regular IO so capture_io works
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.user.create (IDNT-05)" do
    test "creates a user given --handle --email --password" do
      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Create.run([
            "--handle",
            "sysop_a",
            "--email",
            "sysop_a@example.com",
            "--password",
            "correct horse"
          ])
        end)

      assert output =~ "Created user sysop_a"

      user = Accounts.get_user_by_handle("sysop_a")
      assert %User{} = user
      assert user.email == "sysop_a@example.com"
    end

    test "created user is auto-confirmed (D-02)" do
      capture_io(fn ->
        Mix.Tasks.Foglet.User.Create.run([
          "--handle",
          "autoconf",
          "--email",
          "autoconf@example.com",
          "--password",
          "correct horse"
        ])
      end)

      user = Accounts.get_user_by_handle("autoconf")
      assert user.confirmed_at
      assert DateTime.compare(user.confirmed_at, DateTime.utc_now()) in [:lt, :eq]
    end

    test "missing --handle exits {:shutdown, 1} with usage message" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Create.run([
                     "--email",
                     "x@example.com",
                     "--password",
                     "xxxxxxx1"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Missing required flag" or output =~ "Usage:"
    end

    test "missing --email exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.User.Create.run([
                   "--handle",
                   "x",
                   "--password",
                   "xxxxxxx1"
                 ])
               ) == {:shutdown, 1}
      end)
    end

    test "missing --password exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.User.Create.run([
                   "--handle",
                   "x",
                   "--email",
                   "x@example.com"
                 ])
               ) == {:shutdown, 1}
      end)
    end

    test "unknown flag exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.User.Create.run([
                   "--handle",
                   "x",
                   "--email",
                   "x@example.com",
                   "--password",
                   "xxxxxxx1",
                   "--unknown",
                   "value"
                 ])
               ) == {:shutdown, 1}
      end)
    end

    test "duplicate handle exits non-zero with changeset errors" do
      capture_io(fn ->
        Mix.Tasks.Foglet.User.Create.run([
          "--handle",
          "dup",
          "--email",
          "dup1@example.com",
          "--password",
          "correct horse"
        ])
      end)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Create.run([
                     "--handle",
                     "dup",
                     "--email",
                     "dup2@example.com",
                     "--password",
                     "correct horse"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "handle" or output =~ "already been taken"
    end

    test "password below min length exits non-zero" do
      capture_io(:stderr, fn ->
        assert catch_exit(
                 Mix.Tasks.Foglet.User.Create.run([
                   "--handle",
                   "shortpw",
                   "--email",
                   "shortpw@example.com",
                   "--password",
                   "short"
                 ])
               ) == {:shutdown, 1}
      end)
    end
  end
end
