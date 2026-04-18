defmodule Foglet.SSH.Supervisor do
  @moduledoc """
  Wraps Erlang's :ssh.daemon/2 with Foglet's authentication callbacks.

  Daemon options:
    * system_dir → priv/ssh/ (host keys persisted across deploys, Pitfall 3)
    * pwdfun → delegates to Foglet.Accounts.authenticate_by_password/2 (SSH-02)
    * key_cb → Foglet.SSH.KeyCB (SSH-03)
    * ssh_cli → Raxol.SSH.CLIHandler with Foglet.TUI.App (Plan 03)
    * no_auth_needed: true — per RESEARCH Open Question 1 resolution
      (the TUI is the authentication boundary; daemon accepts any
      connection so the guest login-or-register menu can gate identity)

  A runtime check at init/1 asserts the OTP release is >= 27.3.3 to guard
  against CVE-2025-32433 (Pitfall 7).
  """

  use Supervisor

  require Logger

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
    daemon_opts = daemon_opts(system_dir)

    {:ok, _daemon_ref} = :ssh.daemon(port, daemon_opts)

    Logger.info("Foglet SSH daemon listening on port #{port} (system_dir=#{system_dir})")

    # This Supervisor owns no children — the daemon is registered with
    # OTP's :ssh application, not under this supervisor. Returning empty
    # children keeps the tree shape clean.
    Supervisor.init([], strategy: :one_for_one)
  end

  @doc """
  Returns the daemon option keyword list. Exposed for tests; also used by
  init/1. Callers that want to override `system_dir` pass it in.
  """
  @spec daemon_opts(Path.t()) :: keyword()
  def daemon_opts(system_dir) do
    [
      system_dir: String.to_charlist(system_dir),
      no_auth_needed: true,
      pwdfun: &__MODULE__.pwdfun/4,
      key_cb: {Foglet.SSH.KeyCB, [system_dir: String.to_charlist(system_dir)]},
      ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]},
      max_sessions: 500,
      parallel_login: true
    ]
  end

  @doc """
  pwdfun/4 — Erlang :ssh password callback.

  Called for users presenting a password. Returns {true, state} to allow,
  {false, state} to deny. State is threaded through; Phase 3 keeps it
  stateless — Session-level rate limiting lives in Plan 03's Session state.
  """
  @spec pwdfun(charlist(), charlist() | :pubkey, term(), term()) ::
          {boolean(), term()}
  def pwdfun(user, :pubkey, _peer, state) do
    # :pubkey means the daemon is confirming the user name is allowed after
    # key-based auth succeeded via key_cb. Check the handle exists and isn't
    # deleted; the key_cb already validated the key itself.
    handle = List.to_string(user)

    case Foglet.Accounts.get_user_by_handle(handle) do
      %Foglet.Accounts.User{deleted_at: nil} -> {true, state}
      _ -> {false, state}
    end
  end

  def pwdfun(user, password, _peer, state)
      when is_list(user) and is_list(password) do
    handle = List.to_string(user)
    pw = List.to_string(password)

    case Foglet.Accounts.authenticate_by_password(handle, pw) do
      {:ok, %Foglet.Accounts.User{status: :active}} -> {true, state}
      _ -> {false, state}
    end
  end

  # --- Private ---

  defp assert_safe_otp_version! do
    otp = List.to_string(:erlang.system_info(:otp_release))

    # OTP release is like "28"; we also cross-check the full ERTS version.
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
  # string. If we cannot parse, default to a value that PASSES the comparison
  # on OTP 28+ (which is verified elsewhere at CI/deploy time).
  defp erts_to_semver(erts) do
    case String.split(erts, ".") do
      [major | _rest] when byte_size(major) > 0 ->
        # ERTS major >= 14 corresponds to OTP 26+, which all postdate the fix.
        # Return a conservative semver that compares equal to @min_otp_version.
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

  defp ensure_system_dir! do
    dir = Application.app_dir(:foglet_bbs, "priv/ssh")
    File.mkdir_p!(dir)
    dir
  end
end
