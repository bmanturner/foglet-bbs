defmodule Foglet.DoorsTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts.User
  alias Foglet.Doors
  alias Foglet.Sessions.Session

  @demo_doors_env "FOGLET_ENABLE_DEMO_DOORS"
  @production_door_ids ~w[usurper-reborn]
  @demo_door_ids ~w[native-hello external-echo python-context-demo classic-dropfile-demo]

  setup do
    original = System.get_env(@demo_doors_env)
    System.delete_env(@demo_doors_env)
    on_exit(fn -> restore_env(@demo_doors_env, original) end)
    :ok
  end

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

    test "accepts restricted sandbox on classic dropfile manifests" do
      attrs =
        @valid_manifest
        |> Map.merge(%{
          runtime: :classic_dropfile,
          dropfile_formats: [:door32_sys],
          args: ["--door32", "{dropfile:door32_sys}"],
          sandbox: %{
            mode: :restricted_user_process_group,
            user: "foglet-door",
            group: "foglet-door",
            process_tree: :process_group,
            fail_closed?: true
          }
        })

      assert {:ok, manifest} = Doors.validate_manifest(attrs)
      assert manifest.runtime == :classic_dropfile
      assert manifest.dropfile_formats == [:door32_sys]
      assert manifest.sandbox.mode == :restricted_user_process_group
      assert manifest.sandbox.user == "foglet-door"
      assert manifest.sandbox.group == "foglet-door"
      assert manifest.sandbox.process_tree == :process_group
      assert manifest.sandbox.fail_closed? == true
    end

    test "rejects restricted classic dropfile sandbox without a run-as user" do
      attrs =
        @valid_manifest
        |> Map.merge(%{
          runtime: :classic_dropfile,
          dropfile_formats: [:door32_sys],
          sandbox: %{
            mode: :restricted_user_process_group,
            group: "foglet-door",
            process_tree: :process_group,
            fail_closed?: true
          }
        })

      assert {:error, errors} = Doors.validate_manifest(attrs)
      assert {:sandbox_user, "is required for restricted_user_process_group"} in errors
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

    test "normalizes explicit classic dropfile declarations with safe fixed filenames and metadata" do
      attrs =
        Map.merge(@valid_manifest, %{
          runtime: :classic_dropfile,
          dropfiles: [
            %{
              format: :chain_txt,
              identity: :handle,
              transport: :filesystem,
              encoding: :cp437,
              cwd: :door_working_dir,
              expose_path: :env
            },
            %{"format" => "door32_sys"}
          ]
        })

      assert {:ok, manifest} = Doors.validate_manifest(attrs)

      assert manifest.dropfile_formats == [:chain_txt, :door32_sys]

      assert [chain_txt, door32_sys] = manifest.dropfiles
      assert chain_txt.format == :chain_txt
      assert chain_txt.filename == "CHAIN.TXT"
      assert chain_txt.identity == :handle
      assert chain_txt.transport == :filesystem
      assert chain_txt.encoding == :cp437
      assert chain_txt.cwd == :door_working_dir
      assert chain_txt.expose_path == :env

      assert door32_sys.format == :door32_sys
      assert door32_sys.filename == "DOOR32.SYS"
      assert door32_sys.identity == :handle
      assert door32_sys.transport == :filesystem
      assert door32_sys.encoding == :cp437
      assert door32_sys.cwd == :door_working_dir
      assert door32_sys.expose_path == :env
    end

    test "normalizes legacy dropfile_formats into explicit declarations" do
      attrs =
        Map.merge(@valid_manifest, %{
          runtime: :classic_dropfile,
          dropfile_formats: [:chain_txt, :door_sys, :door32_sys, :dorinfo_def]
        })

      assert {:ok, manifest} = Doors.validate_manifest(attrs)

      assert Enum.map(manifest.dropfiles, & &1.filename) == [
               "CHAIN.TXT",
               "DOOR.SYS",
               "DOOR32.SYS",
               "DORINFO.DEF"
             ]

      assert manifest.dropfile_formats == [:chain_txt, :door_sys, :door32_sys, :dorinfo_def]
    end

    test "requires classic dropfile manifests to declare at least one format" do
      attrs = Map.put(@valid_manifest, :runtime, :classic_dropfile)

      assert {:error, errors} = Doors.validate_manifest(attrs)

      assert {:dropfiles, "classic_dropfile doors must declare at least one dropfile format"} in errors
    end

    test "rejects unsafe dropfile paths and filenames from manifests" do
      attrs =
        Map.merge(@valid_manifest, %{
          runtime: :classic_dropfile,
          dropfiles: [
            %{format: :door_sys, filename: "../DOOR.SYS"},
            %{format: :chain_txt, path: "/tmp/CHAIN.TXT"}
          ]
        })

      assert {:error, errors} = Doors.validate_manifest(attrs)

      assert {:dropfiles, "must not declare filenames or paths; Foglet uses fixed safe names"} in errors
    end

    test "denies launch for inactive actors even when the manifest is visible" do
      {:ok, manifest} = Doors.validate_manifest(@valid_manifest)
      suspended = %User{role: :user, status: :suspended, deleted_at: nil}

      assert Doors.launchable?(suspended, manifest) == false
    end
  end

  describe "list_manifests/0" do
    test "includes the production Usurper Reborn DOOR32 manifest without enabling demos" do
      assert [usurper] = Doors.list_manifests()

      assert usurper.id == "usurper-reborn"
      assert usurper.runtime == :classic_dropfile
      assert usurper.command == "/opt/foglet/doors/usurper/UsurperReborn"

      assert usurper.args == [
               "--door32",
               "{dropfile:door32_sys}",
               "--db",
               "/var/lib/foglet/usurper/usurper_online.db",
               "--stdio"
             ]

      assert usurper.working_dir == "/opt/foglet/doors/usurper"
      assert usurper.dropfile_formats == [:door32_sys]
      assert [%{filename: "DOOR32.SYS", identity: :handle, expose_path: :env}] = usurper.dropfiles
    end

    test "hides built-in demo manifests when the env var is absent or empty" do
      assert Enum.map(Doors.list_manifests(), & &1.id) == @production_door_ids

      System.put_env(@demo_doors_env, "")

      assert Enum.map(Doors.list_manifests(), & &1.id) == @production_door_ids
    end

    test "hides built-in demo manifests for false-like env values" do
      for value <- ["0", "false", "no", "off", "random"] do
        System.put_env(@demo_doors_env, value)

        assert Enum.map(Doors.list_manifests(), & &1.id) == @production_door_ids
      end
    end

    test "includes all built-in demo manifests for documented truthy env values" do
      for value <- ["true", "1", "yes", " TRUE ", "Yes"] do
        System.put_env(@demo_doors_env, value)

        assert Enum.map(Doors.list_manifests(), & &1.id) == @production_door_ids ++ @demo_door_ids
      end
    end

    test "uses playable demo timeouts instead of the former five-second cutoff" do
      enable_demo_doors()

      demo_ids = MapSet.new(@demo_door_ids)

      for manifest <- Doors.list_manifests(), manifest.id in demo_ids do
        assert manifest.timeout_ms == 15 * 60 * 1_000
        assert manifest.idle_timeout_ms == 5 * 60 * 1_000
      end
    end

    test "resolves the built-in external echo manifest from application priv when demos are enabled" do
      enable_demo_doors()

      assert external_echo = Enum.find(Doors.list_manifests(), &(&1.id == "external-echo"))
      assert {:ok, priv_dir} = priv_dir()

      assert external_echo.command == Path.join(priv_dir, "doors/demo/external_echo.sh")
      assert external_echo.working_dir == Path.join(priv_dir, "doors/demo")
      assert File.regular?(external_echo.command)
      assert executable?(external_echo.command)
    end
  end

  describe "list_browsable/1" do
    test "derives anonymous browsing from the gated manifest list" do
      assert Doors.list_visible(nil) == []
      assert Enum.map(Doors.list_browsable(nil), & &1.id) == @production_door_ids

      enable_demo_doors()

      assert Doors.list_visible(nil) == []

      assert Enum.map(Doors.list_browsable(nil), & &1.id) ==
               @production_door_ids ++ @demo_door_ids

      assert Enum.all?(Doors.list_browsable(nil), &(&1.visibility == :members))
    end

    test "get_visible/2 respects the gated manifest list" do
      actor = %User{role: :user, status: :active, deleted_at: nil}

      assert {:error, :not_found} = Doors.get_visible(actor, "native-hello")

      enable_demo_doors()

      assert {:ok, manifest} = Doors.get_visible(actor, "native-hello")
      assert manifest.id == "native-hello"
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

    test "generates DOOR.SYS with exact parser-critical classic positions" do
      user = %User{
        id: "user-1",
        handle: "alice",
        real_name: "Alice Liddell",
        role: :mod,
        location: "Wonderland"
      }

      assert {:ok, text} =
               Doors.classic_dropfile(:door_sys, %{
                 user: user,
                 session: session_map(),
                 sysop_name: "Ada Lovelace",
                 time_remaining_minutes: 42,
                 node_number: 7
               })

      lines = dropfile_lines(text)

      assert length(lines) == 40
      assert Enum.at(lines, 0) == "COM0:"
      assert Enum.at(lines, 1) == "38400"
      assert Enum.at(lines, 3) == "7"
      assert Enum.at(lines, 9) == "Alice Liddell"
      assert Enum.at(lines, 10) == "Wonderland"
      assert Enum.at(lines, 15) == "90"
      assert Enum.at(lines, 19) == "42"
      assert Enum.at(lines, 20) == "GR"
      assert Enum.at(lines, 21) == "30"
      assert Enum.at(lines, 25) == "1"
      assert Enum.at(lines, 35) == "Ada Lovelace"
      assert Enum.at(lines, 36) == "alice"
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
      assert Enum.at(lines, 9) == "Guest"
      assert Enum.at(lines, 15) == "50"
      assert Enum.at(lines, 21) == "24"
      assert Enum.at(lines, 25) == "2"
      assert Enum.at(lines, 36) == "guest"
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

      env = Doors.adapter_env(manifest, session_map(), {100, 30}, "/tmp/context.json", paths)

      assert env["FOGLET_DROPFILES"] == Enum.join(Map.values(paths), ":")
      assert env["FOGLET_DROPFILE_DIR"] == tmp
      assert env["FOGLET_DROPFILE_CHAIN_TXT"] == paths.chain_txt
      assert env["FOGLET_DROPFILE_DOOR_SYS"] == paths.door_sys
      assert env["FOGLET_DROPFILE_DORINFO_DEF"] == paths.dorinfo_def
      refute Map.has_key?(env, "FOGLET_DROPFILE_DOOR32_SYS")

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

  defp enable_demo_doors, do: System.put_env(@demo_doors_env, "true")

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} -> Bitwise.band(mode, 0o111) != 0
      _other -> false
    end
  end
end
