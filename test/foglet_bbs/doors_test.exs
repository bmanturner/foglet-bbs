defmodule Foglet.DoorsTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.User
  alias Foglet.Doors
  alias Foglet.Sessions.Session

  @valid_manifest %{
    id: "trade-wars",
    slug: "trade-wars",
    display_name: "Trade Wars",
    description: "Classic space trading door",
    runtime: :external_pty,
    command: "/srv/foglet/doors/tradewars/run.sh",
    args: ["--ansi"],
    working_dir: "/srv/foglet/doors/tradewars",
    env_allowlist: ["TERM", "LANG"],
    timeout_ms: 30_000,
    idle_timeout_ms: 5_000,
    visibility: :members,
    auth_scope: :site
  }

  describe "validate_manifest/1" do
    test "accepts a first-slice external door manifest and normalizes string keys" do
      assert {:ok, manifest} = Doors.validate_manifest(stringify(@valid_manifest))

      assert manifest.id == "trade-wars"
      assert manifest.slug == "trade-wars"
      assert manifest.runtime == :external_pty
      assert manifest.command == "/srv/foglet/doors/tradewars/run.sh"
      assert manifest.args == ["--ansi"]
      assert manifest.env_allowlist == ["TERM", "LANG"]
      assert manifest.timeout_ms == 30_000
      assert manifest.idle_timeout_ms == 5_000
      assert manifest.visibility == :members
    end

    test "rejects unsafe command paths, relative working directories, and non-allowlisted env names" do
      attrs = %{
        @valid_manifest
        | command: "bin/run.sh",
          working_dir: "doors/tradewars",
          env_allowlist: ["TERM", "DATABASE_URL"]
      }

      assert {:error, errors} = Doors.validate_manifest(attrs)
      assert {:command, "must be an absolute path"} in errors
      assert {:working_dir, "must be an absolute path"} in errors
      assert {:env_allowlist, "contains unsupported variable DATABASE_URL"} in errors
    end

    test "denies launch for inactive actors even when the manifest is visible" do
      {:ok, manifest} = Doors.validate_manifest(@valid_manifest)
      suspended = %User{role: :user, status: :suspended, deleted_at: nil}

      assert Doors.launchable?(suspended, manifest) == false
    end
  end

  describe "launch audit redaction" do
    test "redacts non-allowlisted environment metadata and keeps only safe status fields" do
      {:ok, manifest} = Doors.validate_manifest(@valid_manifest)

      audit =
        Doors.launch_audit(%{
          manifest: manifest,
          user: %User{id: "user-1", handle: "alice", role: :user},
          session: %Session{user_id: "user-1", handle: "alice", terminal_size: {100, 30}},
          env: %{"TERM" => "xterm-256color", "DATABASE_URL" => "postgres://secret"},
          status: %{exit_status: 0, reason: :normal, signal: :sigterm, stderr: "secret output"}
        })

      assert audit.door_id == "trade-wars"
      assert audit.user_id == "user-1"
      assert audit.env == %{"TERM" => "xterm-256color", "DATABASE_URL" => "[REDACTED]"}
      assert audit.status == %{exit_status: 0, reason: :normal, signal: :sigterm}
      refute inspect(audit) =~ "postgres://secret"
      refute inspect(audit) =~ "secret output"
    end
  end

  describe "classic_dropfile/2" do
    test "generates CHAIN.TXT fields from session and user metadata" do
      user = %User{id: "user-1", handle: "alice", real_name: "Alice Liddell", role: :user}

      session = %Session{
        user_id: "user-1",
        handle: "alice",
        role: :user,
        terminal_size: {132, 37},
        connected_at: ~U[2026-05-03 20:00:00Z],
        last_seen_at: ~U[2026-05-03 20:15:00Z]
      }

      assert {:ok, text} = Doors.classic_dropfile(:chain_txt, %{user: user, session: session})

      assert text == "alice\r\nAlice Liddell\r\n132\r\n37\r\nuser\r\nuser-1\r\n"
    end
  end

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
