import Config

# In dev, load .env.local (if present) into the process environment so the
# System.get_env reads further down — and the Repo override below — pick it
# up. Real environment variables take precedence over file values.
if config_env() == :dev do
  case Dotenvy.source([".env.local", System.get_env()]) do
    {:ok, vars} ->
      Enum.each(vars, fn {k, v} -> System.put_env(k, v) end)

    {:error, _} ->
      :ok
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/foglet_bbs start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :foglet_bbs, FogletBbsWeb.Endpoint, server: true
end

# SSH daemon port override (env var takes precedence in all envs).
if ssh_port = System.get_env("FOGLET_SSH_PORT") do
  config :foglet_bbs, :ssh_port, String.to_integer(ssh_port)
end

# System-wide default timezone for new user registrations and unauthenticated
# sessions. Must be a valid IANA timezone name (e.g. "America/New_York").
# When unset, falls back to OS-detected timezone, then "Etc/UTC".
# Invalid values are rejected at startup with a logged error.
if tz = System.get_env("FOGLET_DEFAULT_TIMEZONE") do
  config :foglet_bbs, :default_timezone, tz
end

if guest_mode_enabled = System.get_env("FOGLET_GUEST_MODE_ENABLED") do
  guest_mode_enabled =
    case String.downcase(guest_mode_enabled) do
      value when value in ["true", "1"] ->
        true

      value when value in ["false", "0"] ->
        false

      _ ->
        raise "environment variable FOGLET_GUEST_MODE_ENABLED must be one of: true, false, 1, 0"
    end

  config :foglet_bbs, :guest_mode_enabled, guest_mode_enabled
end

if mail_from = System.get_env("FOGLET_MAIL_FROM") do
  config :foglet_bbs, :mail_from, mail_from
end

if smtp_relay = System.get_env("FOGLET_SMTP_RELAY") || System.get_env("FOGLET_SMTP_HOST") do
  config :foglet_bbs, Foglet.Mailer,
    adapter: Swoosh.Adapters.SMTP,
    relay: smtp_relay,
    port: String.to_integer(System.get_env("FOGLET_SMTP_PORT") || "587"),
    username: System.get_env("FOGLET_SMTP_USERNAME"),
    password: System.get_env("FOGLET_SMTP_PASSWORD"),
    ssl: System.get_env("FOGLET_SMTP_SSL") in ~w(true 1),
    tls: String.to_atom(System.get_env("FOGLET_SMTP_TLS") || "if_available"),
    auth: String.to_atom(System.get_env("FOGLET_SMTP_AUTH") || "if_available"),
    tls_options: [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      server_name_indication: String.to_charlist(smtp_relay),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
end

config :foglet_bbs, FogletBbsWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  if database_url = System.get_env("DATABASE_URL") do
    config :foglet_bbs, FogletBbs.Repo, url: database_url
  end
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :foglet_bbs, FogletBbs.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  config :foglet_bbs, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :foglet_bbs, FogletBbsWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  config :foglet_bbs, :ssh, host_key_dir: System.get_env("SSH_HOST_KEY_DIR") || "priv/ssh"

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :foglet_bbs, FogletBbsWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :foglet_bbs, FogletBbsWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
