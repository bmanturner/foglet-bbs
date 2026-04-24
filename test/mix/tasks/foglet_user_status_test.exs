defmodule Mix.Tasks.Foglet.User.StatusTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

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
end
