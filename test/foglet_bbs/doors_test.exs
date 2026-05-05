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
    env: %{},
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
      assert manifest.sandbox.mode == :none
    end

    test "accepts the restricted-user process-group sandbox contract" do
      attrs =
        Map.put(@valid_manifest, :sandbox, %{
          mode: :restricted_user_process_group,
          user: "foglet-door",
          group: "foglet-door",
          process_tree: :process_group,
          fail_closed?: true
        })

      assert {:ok, manifest} = Doors.validate_manifest(attrs)
      assert manifest.sandbox.mode == :restricted_user_process_group
      assert manifest.sandbox.user == "foglet-door"
      assert manifest.sandbox.group == "foglet-door"
      assert manifest.sandbox.process_tree == :process_group
      assert manifest.sandbox.fail_closed? == true
    end

    test "rejects unsafe command paths, relative working directories, and unsafe env names" do
      attrs = %{
        @valid_manifest
        | command: "bin/run.sh",
          working_dir: "doors/tradewars",
          env: %{"DATABASE_URL" => "postgres://secret"},
          env_allowlist: ["TERM", "DATABASE_URL"]
      }

      assert {:error, errors} = Doors.validate_manifest(attrs)
      assert {:command, "must be an absolute path"} in errors
      assert {:working_dir, "must be an absolute path"} in errors
      assert {:env, "contains unsupported variable DATABASE_URL"} in errors
      assert {:env_allowlist, "contains unsupported variable DATABASE_URL"} in errors
    end

    test "rejects unsafe explicit env and incomplete sandbox contracts" do
      attrs =
        @valid_manifest
        |> Map.put(:env, %{"DATABASE_URL" => "postgres://secret"})
        |> Map.put(:sandbox, %{mode: :restricted_user_process_group})

      assert {:error, errors} = Doors.validate_manifest(attrs)
      assert {:env, "contains unsupported variable DATABASE_URL"} in errors
      assert {:sandbox_user, "is required for restricted_user_process_group"} in errors
    end

    test "rejects non-string manifest env values" do
      attrs = %{@valid_manifest | env: %{"TERM" => :xterm}}

      assert {:error, errors} = Doors.validate_manifest(attrs)
      assert {:env, "contains non-string value for TERM"} in errors
    end

    test "denies launch for inactive actors even when the manifest is visible" do
      {:ok, manifest} = Doors.validate_manifest(@valid_manifest)
      suspended = %User{role: :user, status: :suspended, deleted_at: nil}

      assert Doors.launchable?(suspended, manifest) == false
    end
  end

  describe "list_manifests/0" do
    test "resolves the built-in external echo manifest from application priv" do
      assert external_echo = Enum.find(Doors.list_manifests(), &(&1.id == "external-echo"))
      assert {:ok, priv_dir} = priv_dir()

      assert external_echo.command == Path.join(priv_dir, "doors/demo/external_echo.sh")
      assert external_echo.working_dir == Path.join(priv_dir, "doors/demo")
      assert File.regular?(external_echo.command)
      assert executable?(external_echo.command)
    end
  end

  describe "list_browsable/1" do
    test "keeps anonymous browsing separate from launch authorization" do
      assert Doors.list_visible(nil) == []
      assert [_ | _] = Doors.list_browsable(nil)
      assert Enum.all?(Doors.list_browsable(nil), &(&1.visibility == :members))
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
    test "generates CHAIN.TXT fields from session and user metadata without changing first-slice output" do
      user = %User{id: "user-1", handle: "alice", real_name: "Alice Liddell", role: :user}
      session = session_fixture()

      assert {:ok, text} = Doors.classic_dropfile(:chain_txt, %{user: user, session: session})

      assert text == "alice\r\nAlice Liddell\r\n132\r\n37\r\nuser\r\nuser-1\r\n"
      assert_crlf_terminated(text)
    end

    test "generates DOOR.SYS with safe Foglet metadata and conservative defaults" do
      user = %User{
        id: "user-1",
        handle: "alice",
        real_name: "Alice Liddell",
        role: :mod,
        location: "Wonderland"
      }

      assert {:ok, text} =
               Doors.classic_dropfile(:door_sys, %{user: user, session: session_map()})

      lines = dropfile_lines(text)

      assert length(lines) == 40
      assert Enum.at(lines, 0) == "COM0:"
      assert Enum.at(lines, 3) == "Foglet BBS"
      assert Enum.at(lines, 4) == "alice"
      assert Enum.at(lines, 5) == "Alice Liddell"
      assert Enum.at(lines, 6) == "Wonderland"
      assert Enum.at(lines, 8) == "100"
      assert Enum.at(lines, 9) == "30"
      assert Enum.at(lines, 19) == "user-1"
      assert Enum.at(lines, 32) == "mod"
      assert Enum.at(lines, 39) == "session-1"
      assert_crlf_terminated(text)
    end

    test "generates DORINFO.DEF with safe Foglet metadata and role security level" do
      user = %User{id: "user-1", handle: "alice", real_name: "Alice Liddell", role: :sysop}

      assert {:ok, text} =
               Doors.classic_dropfile(:dorinfo_def, %{user: user, session: session_fixture()})

      assert dropfile_lines(text) == [
               "Foglet BBS",
               "Foglet",
               "Sysop",
               "COM0",
               "38400 BAUD,N,8,1",
               "0",
               "alice",
               "Alice Liddell",
               "",
               "100"
             ]

      assert_crlf_terminated(text)
    end

    test "dropfiles use fallback/default metadata without leaking app secrets" do
      assert {:ok, text} =
               Doors.classic_dropfile(:door_sys, %{
                 user: %User{id: "user-2", role: :user},
                 session: %Session{user_id: "user-2"}
               })

      lines = dropfile_lines(text)
      assert Enum.at(lines, 4) == "guest"
      assert Enum.at(lines, 5) == "Guest"
      assert Enum.at(lines, 8) == "80"
      assert Enum.at(lines, 9) == "24"
      refute text =~ "DATABASE_URL"
      refute text =~ "SECRET"
    end
  end

  describe "adapter context/env/dropfile helpers" do
    test "builds minimal wrapper env/context and writes requested dropfiles with fixed names" do
      {:ok, manifest} =
        Doors.validate_manifest(
          Map.merge(@valid_manifest, %{
            runtime: :classic_dropfile,
            dropfile_formats: [:chain_txt, :door_sys, :dorinfo_def]
          })
        )

      context = Doors.adapter_context(manifest, session_map(), {100, 30})
      env = Doors.adapter_env(manifest, session_map(), {100, 30}, "/tmp/context.json")

      assert context == %{
               door_id: "trade-wars",
               user_id: "user-1",
               handle: "alice",
               role: :user,
               session_id: "session-1",
               terminal_width: 100,
               terminal_height: 30
             }

      assert env["FOGLET_DOOR_CONTEXT"] == "/tmp/context.json"
      assert env["FOGLET_USERNAME"] == "alice"
      refute Map.has_key?(env, "DATABASE_URL")

      tmp =
        Path.join(System.tmp_dir!(), "foglet-dropfile-test-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      assert {:ok, paths} =
               Doors.write_dropfiles(
                 manifest.dropfile_formats,
                 %{user: session_map(), session: session_map()},
                 tmp
               )

      assert paths.chain_txt == Path.join(tmp, "CHAIN.TXT")
      assert paths.door_sys == Path.join(tmp, "DOOR.SYS")
      assert paths.dorinfo_def == Path.join(tmp, "DORINFO.DEF")
      assert File.read!(paths.chain_txt) =~ "alice\r\nAlice Liddell\r\n100\r\n30"
    end
  end

  defp session_fixture do
    %Session{
      user_id: "user-1",
      handle: "alice",
      role: :user,
      terminal_size: {132, 37},
      connected_at: ~U[2026-05-03 20:00:00Z],
      theme: nil
    }
  end

  defp session_map do
    %{
      user_id: "user-1",
      handle: "alice",
      real_name: "Alice Liddell",
      role: :user,
      session_id: "session-1",
      terminal_size: {100, 30}
    }
  end

  defp assert_crlf_terminated(text) do
    assert String.ends_with?(text, "\r\n")
    refute text =~ ~r/(?<!\r)\n/
  end

  defp dropfile_lines(text) do
    text
    |> String.split("\r\n", trim: false)
    |> List.delete_at(-1)
  end

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp priv_dir do
    case :code.priv_dir(:foglet_bbs) do
      path when is_list(path) -> {:ok, List.to_string(path)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _other -> false
    end
  end
end
