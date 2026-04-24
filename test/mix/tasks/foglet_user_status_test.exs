defmodule Mix.Tasks.Foglet.User.StatusTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias FogletBbs.AccountsFixtures

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "argument validation" do
    test "missing target handle exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run(["--status", "active", "--actor", "root"])
                 ) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Missing required target handle."
    end

    test "missing --status exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.User.Status.run(["pending_user", "--actor", "root"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Missing required --status flag."
    end

    test "missing --actor exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run(["pending_user", "--status", "active"])
                 ) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Missing required --actor flag."
    end

    test "invalid status exits non-zero without atom creation" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run([
                     "pending_user",
                     "--status",
                     "banned",
                     "--actor",
                     "root"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ ~s(Invalid status: "banned". Valid statuses: active, rejected, suspended)
    end
  end

  describe "status transitions" do
    test "changes pending user to active and prints notification outcome" do
      sysop_fixture("root")
      user_with_status(:pending, "pending_user")

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Status.run([
            "pending_user",
            "--status",
            "active",
            "--actor",
            "root"
          ])
        end)

      assert output =~
               "Changed pending_user from pending to active. Notification: skipped_no_email"

      assert Accounts.get_user_by_handle("pending_user").status == :active
    end

    test "changes pending user to rejected" do
      sysop_fixture("rejector")
      user_with_status(:pending, "pending_reject")

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Status.run([
            "pending_reject",
            "--status",
            "rejected",
            "--actor",
            "rejector"
          ])
        end)

      assert output =~
               "Changed pending_reject from pending to rejected. Notification: skipped_no_email"

      assert Accounts.get_user_by_handle("pending_reject").status == :rejected
    end

    test "changes active user to suspended" do
      sysop_fixture("suspender")
      AccountsFixtures.user_fixture(%{handle: "active_suspend"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Status.run([
            "active_suspend",
            "--status",
            "suspended",
            "--actor",
            "suspender"
          ])
        end)

      assert output =~
               "Changed active_suspend from active to suspended. Notification: not_applicable"

      assert Accounts.get_user_by_handle("active_suspend").status == :suspended
    end

    test "changes suspended user to active" do
      sysop_fixture("reactivator")
      user_with_status(:suspended, "suspactive")

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.User.Status.run([
            "suspactive",
            "--status",
            "active",
            "--actor",
            "reactivator"
          ])
        end)

      assert output =~
               "Changed suspactive from suspended to active. Notification: not_applicable"

      assert Accounts.get_user_by_handle("suspactive").status == :active
    end

    test "prints forbidden for non-sysop actor" do
      AccountsFixtures.user_fixture(%{handle: "regular_actor"})
      user_with_status(:pending, "forbidden_target")

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run([
                     "forbidden_target",
                     "--status",
                     "active",
                     "--actor",
                     "regular_actor"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Forbidden."
      assert Accounts.get_user_by_handle("forbidden_target").status == :pending
    end

    test "prints user not found for unknown actor or target" do
      sysop_fixture("finder")

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run([
                     "missing_target",
                     "--status",
                     "active",
                     "--actor",
                     "finder"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "User not found."

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run([
                     "missing_target",
                     "--status",
                     "active",
                     "--actor",
                     "missing_actor"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "User not found."
    end

    test "prints invalid status transition for disallowed graph edge" do
      sysop_fixture("invalidator")
      AccountsFixtures.user_fixture(%{handle: "active_reject"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.User.Status.run([
                     "active_reject",
                     "--status",
                     "rejected",
                     "--actor",
                     "invalidator"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Invalid status transition."
      assert Accounts.get_user_by_handle("active_reject").status == :active
    end
  end

  defp sysop_fixture(handle) do
    user = AccountsFixtures.user_fixture(%{handle: handle})
    {:ok, sysop} = Accounts.update_role(user, :sysop)
    sysop
  end

  defp user_with_status(status, handle) do
    AccountsFixtures.user_fixture(%{handle: handle})
    |> User.status_changeset(%{status: status})
    |> Repo.update!()
  end
end
