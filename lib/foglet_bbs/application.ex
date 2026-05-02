defmodule FogletBbs.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    validate_default_timezone()

    # Initialize the runtime-config ETS cache before any supervised
    # process might read from it. Idempotent on warm restarts.
    Foglet.Config.init_cache()

    # Initialize the pubkey stash ETS table used by Foglet.SSH.KeyCB and
    # Foglet.SSH.CLIHandler for pubkey-to-user correlation on connection.
    Foglet.SSH.PubkeyStash.init()

    # Register TUI themes with Raxol's theme registry so widgets and
    # future user-selectable switching can look them up by id.
    Foglet.TUI.Theme.register_all()

    children = base_children() ++ ssh_children()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FogletBbs.Supervisor]
    {:ok, sup} = Supervisor.start_link(children, opts)
    Foglet.Boards.boot_board_servers()
    {:ok, sup}
  end

  defp base_children do
    [
      FogletBbsWeb.Telemetry,
      FogletBbs.Repo,
      {DNSCluster, query: Application.get_env(:foglet_bbs, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FogletBbs.PubSub},
      {Registry, keys: :unique, name: Foglet.BoardRegistry},
      Foglet.Boards.Supervisor,
      {Registry, keys: :unique, name: Foglet.Sessions.Registry},
      Foglet.Sessions.Supervisor,
      Foglet.Sessions.BoardScreen,
      {Registry, keys: :unique, name: Foglet.BoardChat.Ephemeral.Registry},
      Foglet.BoardChat.Ephemeral.Supervisor,
      # Start to serve requests, typically the last entry
      FogletBbsWeb.Endpoint
    ]
  end

  defp ssh_children do
    if Application.get_env(:foglet_bbs, :start_ssh_daemon, true) do
      [Foglet.SSH.Supervisor]
    else
      []
    end
  end

  defp validate_default_timezone do
    case Application.get_env(:foglet_bbs, :default_timezone) do
      nil ->
        :ok

      tz when is_binary(tz) ->
        unless Timex.Timezone.exists?(tz) do
          Logger.error(
            "FOGLET_DEFAULT_TIMEZONE=#{inspect(tz)} is not a valid IANA timezone name. " <>
              "New users and unauthenticated sessions will fall back to the OS-detected " <>
              "timezone. Set a valid IANA name such as \"America/New_York\" or \"Europe/London\"."
          )
        end

      other ->
        Logger.error(
          "FOGLET_DEFAULT_TIMEZONE has unexpected value #{inspect(other)} — ignoring. " <>
            "Set a valid IANA name such as \"America/New_York\" or \"Europe/London\"."
        )
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FogletBbsWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
