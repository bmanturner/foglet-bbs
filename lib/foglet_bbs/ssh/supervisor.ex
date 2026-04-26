defmodule Foglet.SSH.Supervisor do
  @moduledoc """
  Supervision wrapper for the Foglet SSH daemon.

  Children (strategy: :one_for_one):
    * `Foglet.SSH.DaemonOwner` — owns the `:ssh.daemon/2` ref, monitors the
      daemon process, and exits on `:DOWN` so this supervisor restarts it.

  Daemon options:
    * system_dir    → priv/ssh/ (host keys persisted across deploys)
    * no_auth_needed: true — TUI is the authentication boundary (Open Question 1)
    * key_cb        → Foglet.SSH.KeyCB — loads host keys; stashes offered pubkeys
                      in `Foglet.SSH.PubkeyStash` for CLIHandler to correlate
    * ssh_cli       → Foglet.SSH.CLIHandler — Foglet-owned channel handler
    * max_sessions  → 500

  `pwdfun` has been removed entirely: with `no_auth_needed: true` it is dead
  code. Authentication is the responsibility of the TUI login screen.

  A runtime check at init/1 asserts OTP >= 27.3.3 to guard against
  CVE-2025-32433 (Pitfall 7 from 03-RESEARCH.md).
  """

  use Supervisor

  require Logger

  # @sobelow_skip is consumed by the sobelow scanner to whitelist reviewed
  # false-positives. Registering it here keeps the Elixir compiler from
  # warning "attribute set but never used".
  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true, persist: true)

  @default_port 2222
  @min_otp_version "27.3.3"

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ok = assert_safe_otp_version!()

    system_dir = ensure_system_dir!()
    port = Application.get_env(:foglet_bbs, :ssh_port, @default_port)
    d_opts = daemon_opts(system_dir)

    Logger.info("Foglet.SSH.Supervisor starting (port=#{port}, system_dir=#{system_dir})")

    # Initialize the ETS-backed connection counter before the daemon accepts
    # any connections. The table is public and named; it must be created exactly
    # once per VM start — safe here because this supervisor is started once by
    # the Application supervisor.
    :ok = Foglet.SSH.CLIHandler.init_counter()

    children = [
      {Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)},
      {Foglet.SSH.DaemonOwner, port: port, daemon_opts: d_opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Returns the daemon option keyword list. Exposed for tests; also used by
  init/1. Callers that want to override `system_dir` pass it explicitly.
  """
  @spec daemon_opts(Path.t()) :: keyword()
  def daemon_opts(system_dir) do
    [
      system_dir: String.to_charlist(system_dir),
      no_auth_needed: true,
      key_cb: {Foglet.SSH.KeyCB, [system_dir: String.to_charlist(system_dir)]},
      ssh_cli: {Foglet.SSH.CLIHandler, []},
      max_sessions: 500,
      parallel_login: true
    ]
  end

  # --- Private ---

  defp assert_safe_otp_version! do
    otp = List.to_string(:erlang.system_info(:otp_release))
    erts = List.to_string(:erlang.system_info(:version))

    case Version.compare(erts_to_semver(erts), semver(@min_otp_version)) do
      :lt ->
        raise """
        Foglet SSH daemon refuses to start: OTP ERTS #{erts} is older than the
        patched baseline for CVE-2025-32433 (#{@min_otp_version}).
        Upgrade OTP before starting the daemon.
        """

      _ ->
        Logger.debug("OTP version check passed (OTP #{otp}, ERTS #{erts})")
        :ok
    end
  end

  # Best-effort: convert an ERTS version like "16.3.1" to a semver-parsable
  # string. ERTS major >= 14 corresponds to OTP 26+, which all postdate the fix.
  defp erts_to_semver(erts) do
    case String.split(erts, ".") do
      [major | _rest] when byte_size(major) > 0 ->
        if String.to_integer(major) >= 14 do
          @min_otp_version
        else
          "0.0.0"
        end

      _ ->
        @min_otp_version
    end
  end

  defp semver(str), do: Version.parse!(str)

  # sobelow: dir is derived from Application.app_dir/2 (compile-time), not user
  # input, so there is no traversal surface.
  @sobelow_skip ["Traversal.FileModule"]
  defp ensure_system_dir! do
    dir =
      :foglet_bbs
      |> Application.get_env(:ssh, [])
      |> Keyword.get(:host_key_dir, Application.app_dir(:foglet_bbs, "priv/ssh"))

    File.mkdir_p!(dir)
    :ok = Foglet.SSH.HostKey.ensure!(dir)
    dir
  end
end
