import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :foglet_bbs, FogletBbs.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "foglet_bbs_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :foglet_bbs, FogletBbsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QVKe5V+pSbjCG9N3RMj/Ji3Ps2QAGlXXxV5qFJ7yrNgOmjTqI5itBmDii7Z0EeCe",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# Make Argon2 fast in tests (insecure params — test-only)
config :argon2_elixir, t_cost: 1, m_cost: 8

# Never start the SSH daemon during tests — tests exercise it directly
# via start_supervised!/1 on Foglet.SSH.Supervisor with test-specific opts.
config :foglet_bbs, :start_ssh_daemon, false
