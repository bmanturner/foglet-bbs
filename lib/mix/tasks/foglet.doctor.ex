defmodule Mix.Tasks.Foglet.Doctor do
  use Mix.Task

  @moduledoc "Verifies the development environment is correctly configured."
  @shortdoc "Verifies the development environment is correctly configured"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:postgrex)

    checks = [
      {"Elixir version", &check_elixir_version/0},
      {"Erlang version", &check_erlang_version/0},
      {"Postgres reachable", &check_postgres/0},
      {"citext extension", &check_citext/0},
      {"SSH host key", &check_ssh_key/0},
      {"Environment variables", &check_env_vars/0}
    ]

    results =
      Enum.map(checks, fn {label, check} ->
        case check.() do
          :ok ->
            Mix.shell().info("  [OK]   #{label}")
            :ok

          {:error, msg} ->
            Mix.shell().error("  [FAIL] #{label}: #{msg}")
            :error
        end
      end)

    if :error in results do
      Mix.shell().error("\nDoctor found problems. Fix them before proceeding.")
      exit({:shutdown, 1})
    else
      Mix.shell().info("\nAll checks passed.")
    end
  end

  defp check_elixir_version do
    case parse_tool_versions("elixir") do
      nil ->
        {:error, ".tool-versions missing elixir entry"}

      expected ->
        actual = System.version()
        expected_clean = Regex.replace(~r/-otp-\d+$/, expected, "")

        if actual == expected_clean,
          do: :ok,
          else: {:error, "expected #{expected_clean}, running #{actual}"}
    end
  end

  defp check_erlang_version do
    case parse_tool_versions("erlang") do
      nil ->
        {:error, ".tool-versions missing erlang entry"}

      expected ->
        actual = to_string(:erlang.system_info(:otp_release))
        expected_major = expected |> String.split(".") |> List.first()

        if actual == expected_major,
          do: :ok,
          else: {:error, "expected OTP #{expected_major}, running OTP #{actual}"}
    end
  end

  defp parse_tool_versions(tool) do
    case File.read(".tool-versions") do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.find_value(&parse_tool_line(&1, tool))

      _ ->
        nil
    end
  end

  defp parse_tool_line(line, tool) do
    case String.split(line, ~r/\s+/, parts: 2) do
      [^tool, version] -> String.trim(version)
      _ -> nil
    end
  end

  defp repo_config do
    Application.get_env(:foglet_bbs, FogletBbs.Repo, [])
  end

  defp connect_postgres(database) do
    cfg = repo_config()

    Postgrex.start_link(
      hostname: cfg[:hostname] || "localhost",
      port: cfg[:port] || 5432,
      username: cfg[:username] || "postgres",
      password: cfg[:password] || "postgres",
      database: database,
      timeout: 5_000
    )
  end

  defp check_postgres do
    case connect_postgres("postgres") do
      {:ok, pid} ->
        GenServer.stop(pid)
        :ok

      {:error, reason} ->
        {:error, "cannot connect (#{inspect(reason)})"}
    end
  end

  defp check_citext do
    cfg = repo_config()
    db = cfg[:database] || "foglet_bbs_dev"

    case connect_postgres(db) do
      {:ok, pid} ->
        result = Postgrex.query(pid, "SELECT 1 FROM pg_extension WHERE extname = 'citext'", [])
        GenServer.stop(pid)

        case result do
          {:ok, %{rows: [[1]]}} ->
            :ok

          _ ->
            {:error, "not installed in #{db}. Run: CREATE EXTENSION IF NOT EXISTS citext;"}
        end

      {:error, _} ->
        {:error, "database #{db} not reachable — run mix ecto.create first"}
    end
  end

  defp check_ssh_key do
    path = "priv/ssh/host_key"

    if File.exists?(path),
      do: :ok,
      else: {:error, "#{path} missing. Generate: ssh-keygen -t ed25519 -f #{path} -N \"\""}
  end

  defp check_env_vars do
    required =
      case Mix.env() do
        :prod -> ~w[DATABASE_URL SECRET_KEY_BASE PHX_HOST]
        _ -> []
      end

    missing = Enum.reject(required, &System.get_env/1)

    if missing == [],
      do: :ok,
      else: {:error, "missing: #{Enum.join(missing, ", ")}"}
  end
end
