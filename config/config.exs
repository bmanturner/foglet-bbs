# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :foglet_bbs,
  ecto_repos: [FogletBbs.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :foglet_bbs, FogletBbsWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FogletBbsWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FogletBbs.PubSub,
  live_view: [signing_salt: "UCDYsbrB"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Default outbound mail adapter. Production deployments can override this in
# runtime config with env-backed SMTP settings.
config :foglet_bbs, Foglet.Mailer, adapter: Swoosh.Adapters.Local

# Disable Raxol's performance monitoring feature to prevent a DevHints startup crash
# (Raxol 2.4.0 bug: DevHints.normalize_init_result/1 doesn't handle :ignore when
# the module was compiled in test env and @mix_env == :dev evaluates to false).
config :raxol,
  features: %{
    database: false,
    pubsub: true,
    web_interface: false,
    terminal_driver: true,
    performance_monitoring: false,
    terminal_sync: true,
    rate_limiting: true,
    telemetry: true,
    plugins: false,
    audit: false,
    dev_performance_hints: false
  }

# SSH daemon configuration (Phase 3)
config :foglet_bbs, :ssh_port, 2222
config :foglet_bbs, :start_ssh_daemon, true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
