defmodule Mix.Tasks.Foglet.Doctor do
  use Mix.Task

  @requirements ["app.config"]

  @moduledoc "Verifies the development environment is correctly configured."
  @shortdoc "Verifies the development environment is correctly configured"

  @impl Mix.Task
  def run(_args) do
    {:ok, _} = Application.ensure_all_started(:postgrex)

    Mix.shell().info(
      "Foglet doctor: safe local checks only; no network calls or destructive DB changes.\n"
    )

    checks = [
      {"Elixir version", &check_elixir_version/0},
      {"Erlang/OTP version", &check_erlang_version/0},
      {"Configured database reachable", &check_database/0},
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
      Mix.shell().error(
        "\nDoctor found problems. Fix the failed items above, then re-run rtk mix foglet.doctor."
      )

      exit({:shutdown, 1})
    else
      Mix.shell().info(
        "\nAll checks passed. Next: rtk mix phx.server, then ssh -p 2222 sysop@localhost."
      )
    end
  end

  defp check_elixir_version do
    case expected_tool_version("elixir") do
      nil ->
        {:error, ".tool-versions is missing an elixir entry; run from the repo root."}

      expected ->
        actual = System.version()
        expected_clean = elixir_version_without_otp_suffix(expected)

        if actual == expected_clean do
          :ok
        else
          {:error,
           "expected #{expected_clean}, running #{actual}. " <>
             "Run `asdf install`/mise from the repo root or enter through `rtk`."}
        end
    end
  end

  defp check_erlang_version do
    case expected_tool_version("erlang") do
      nil ->
        {:error, ".tool-versions is missing an erlang entry; run from the repo root."}

      expected ->
        actual = to_string(:erlang.system_info(:otp_release))
        expected_major = expected |> String.split(".") |> List.first()

        if actual == expected_major do
          :ok
        else
          {:error,
           "expected OTP #{expected_major} from erlang #{expected}, running OTP #{actual}. " <>
             "Install the pinned Erlang/OTP with `asdf install`/mise or use `rtk`."}
        end
    end
  end

  defp expected_tool_version(tool) do
    case File.read(".tool-versions") do
      {:ok, content} -> parse_tool_versions(content, tool)
      _ -> nil
    end
  end

  @doc false
  def parse_tool_versions(content, tool) when is_binary(content) and is_binary(tool) do
    content
    |> String.split("\n", trim: true)
    |> Enum.find_value(&parse_tool_line(&1, tool))
  end

  defp parse_tool_line(line, tool) do
    line = line |> String.split("#", parts: 2) |> hd() |> String.trim()

    case String.split(line, ~r/\s+/, trim: true) do
      [^tool, version | _] -> version
      _ -> nil
    end
  end

  defp elixir_version_without_otp_suffix(version) do
    Regex.replace(~r/-otp-\d+$/, version, "")
  end

  defp repo_config do
    cfg = Application.get_env(:foglet_bbs, FogletBbs.Repo, [])

    cfg
    |> Keyword.get(:url, "")
    |> Ecto.Repo.Supervisor.parse_url()
    |> Keyword.merge(cfg)
  end

  defp configured_database do
    repo_config()[:database] || "foglet_bbs_dev"
  end

  defp connection_opts(database) do
    cfg = repo_config()

    [
      hostname: cfg[:hostname] || "localhost",
      port: cfg[:port] || 5432,
      username: cfg[:username] || "postgres",
      password: cfg[:password] || "postgres",
      database: database,
      timeout: 5_000
    ]
  end

  defp connect_database(database) do
    Postgrex.start_link(connection_opts(database))
  end

  defp check_database do
    db = configured_database()

    case connect_database(db) do
      {:ok, pid} ->
        result = Postgrex.query(pid, "SELECT 1", [])
        GenServer.stop(pid)

        case result do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, database_query_failure_message(db, reason)}
        end

      {:error, reason} ->
        {:error, database_connection_failure_message(db, reason)}
    end
  end

  defp check_citext do
    db = configured_database()

    case connect_database(db) do
      {:ok, pid} ->
        result = Postgrex.query(pid, "SELECT 1 FROM pg_extension WHERE extname = 'citext'", [])
        GenServer.stop(pid)

        case result do
          {:ok, %{rows: [[1]]}} ->
            :ok

          {:ok, _} ->
            {:error,
             "not installed in #{db}. Run `rtk mix ecto.migrate`; the first migration creates citext."}

          {:error, reason} ->
            {:error, database_query_failure_message(db, reason)}
        end

      {:error, reason} ->
        {:error, database_connection_failure_message(db, reason)}
    end
  end

  @doc false
  def database_connection_failure_message(db, %Postgrex.Error{
        postgres: %{code: :invalid_catalog_name}
      }) do
    "database #{db} does not exist. Run `rtk mix ecto.create` or full setup with `rtk mix setup`."
  end

  def database_connection_failure_message(_db, %DBConnection.ConnectionError{} = reason) do
    "cannot reach Postgres (#{Exception.message(reason)}). " <>
      "Start it with `docker compose up -d postgres`, or set DATABASE_URL to the running database."
  end

  def database_connection_failure_message(_db, %Postgrex.Error{} = reason) do
    "Postgres rejected the connection (#{Exception.message(reason)}). " <>
      "Check config/dev.exs or DATABASE_URL credentials and host/port."
  end

  def database_connection_failure_message(db, reason) do
    "cannot connect to #{db} (#{inspect(reason)}). " <>
      "Start Postgres or run `rtk mix setup` after the database is available."
  end

  defp database_query_failure_message(db, reason) do
    "query failed against #{db} (#{inspect(reason)}). Check database permissions and migrations."
  end

  defp check_ssh_key do
    dir =
      :foglet_bbs
      |> Application.get_env(:ssh, [])
      |> Keyword.get(:host_key_dir, Application.app_dir(:foglet_bbs, "priv/ssh"))

    try do
      Foglet.SSH.HostKey.ensure!(dir)
      :ok
    rescue
      error ->
        {:error,
         "could not ensure host key in #{dir}: #{Exception.message(error)}. " <>
           "Install ssh-keygen and make SSH_HOST_KEY_DIR/app priv/ssh writable."}
    end
  end

  defp check_env_vars do
    required =
      case Mix.env() do
        :prod -> ~w[DATABASE_URL SECRET_KEY_BASE PHX_HOST]
        _ -> []
      end

    missing = Enum.reject(required, &System.get_env/1)

    if missing == [] do
      :ok
    else
      {:error,
       "missing #{Enum.join(missing, ", ")}. Set the required production env vars before release/startup."}
    end
  end
end
