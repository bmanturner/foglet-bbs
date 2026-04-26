defmodule Foglet.SSH.HostKey do
  @moduledoc """
  Ensures an SSH host key exists in the configured `system_dir`.

  Generates an Ed25519 key on first boot if none of the standard
  `ssh_host_*_key` files are present. Idempotent: a no-op when a key already
  exists, so the SSH fingerprint stays stable across deploys as long as the
  underlying volume persists.
  """

  require Logger

  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true, persist: true)

  # Mirrors the filenames Erlang's :ssh_file.host_key/2 looks for.
  @host_key_files ~w[
    ssh_host_ed25519_key
    ssh_host_ecdsa_key
    ssh_host_rsa_key
    ssh_host_dsa_key
  ]

  @default_filename "ssh_host_ed25519_key"

  # sobelow: `dir` is sourced from app config (SSH_HOST_KEY_DIR / app_dir),
  # not user input — no traversal surface.
  @sobelow_skip ["Traversal.FileModule"]
  @spec ensure!(Path.t()) :: :ok
  def ensure!(dir) do
    File.mkdir_p!(dir)

    if has_host_key?(dir) do
      :ok
    else
      generate!(dir)
    end
  end

  defp has_host_key?(dir) do
    Enum.any?(@host_key_files, fn name -> File.regular?(Path.join(dir, name)) end)
  end

  # sobelow: ssh-keygen path is constant; `dir` originates from app config
  # (SSH_HOST_KEY_DIR) and the filename is a module constant — no user input.
  @sobelow_skip ["CI.System", "Traversal.FileModule"]
  defp generate!(dir) do
    path = Path.join(dir, @default_filename)
    Logger.info("Foglet.SSH.HostKey: no host key in #{dir}, generating #{@default_filename}")

    case System.cmd("ssh-keygen", ["-t", "ed25519", "-f", path, "-N", "", "-q"],
           stderr_to_stdout: true
         ) do
      {_out, 0} ->
        File.chmod!(path, 0o600)
        :ok

      {out, status} ->
        raise "ssh-keygen failed (exit #{status}) generating #{path}: #{out}"
    end
  end
end
