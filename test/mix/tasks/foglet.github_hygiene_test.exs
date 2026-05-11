defmodule Mix.Tasks.Foglet.GithubHygieneTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.github_hygiene" do
    test "accepts clean branch, commit subject, PR title, and PR body" do
      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.GithubHygiene.run([
            "--branch",
            "work/add-runtime-guardrails",
            "--commit-subject",
            "ci: add metadata hygiene workflow",
            "--pr-title",
            "ci: add metadata hygiene workflow",
            "--pr-body",
            "Summary without private tracker IDs"
          ])
        end)

      assert output =~ "GitHub metadata hygiene check passed"
    end

    test "rejects Paperclip identifiers in branch names" do
      stderr =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, fn ->
            Mix.Tasks.Foglet.GithubHygiene.run([
              "--branch",
              "work/FOG-1208-metadata-hygiene",
              "--commit-subject",
              "ci: add metadata hygiene workflow",
              "--pr-title",
              "ci: add metadata hygiene workflow"
            ])
          end
        end)

      assert stderr =~ "branch name"
      assert stderr =~ "FOG-1208"
    end

    test "rejects non-conventional commit subjects" do
      stderr =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, fn ->
            Mix.Tasks.Foglet.GithubHygiene.run([
              "--branch",
              "work/add-runtime-guardrails",
              "--commit-subject",
              "Add metadata hygiene workflow",
              "--pr-title",
              "ci: add metadata hygiene workflow"
            ])
          end
        end)

      assert stderr =~ "commit subject"
      assert stderr =~ "Conventional Commit"
    end

    test "rejects Paperclip identifiers in PR body without override" do
      stderr =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, fn ->
            Mix.Tasks.Foglet.GithubHygiene.run([
              "--branch",
              "work/add-runtime-guardrails",
              "--commit-subject",
              "ci: add metadata hygiene workflow",
              "--pr-title",
              "ci: add metadata hygiene workflow",
              "--pr-body",
              "Implements FOG-1208."
            ])
          end
        end)

      assert stderr =~ "PR description"
      assert stderr =~ "FOG-1208"
    end

    test "allows PR body override when explicitly requested" do
      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.GithubHygiene.run([
            "--branch",
            "work/add-runtime-guardrails",
            "--commit-subject",
            "ci: add metadata hygiene workflow",
            "--pr-title",
            "ci: add metadata hygiene workflow",
            "--pr-body",
            "Implements FOG-1208.",
            "--allow-paperclip-ids-in-pr-body"
          ])
        end)

      assert output =~ "GitHub metadata hygiene check passed"
      assert output =~ "Override active"
    end
  end
end
