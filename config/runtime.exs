import Config

# Load .env file if present (development convenience)
if config_env() == :dev do
  Dotenv.load()
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
#     PHX_SERVER=true bin/msfailab start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :msfailab, MsfailabWeb.Endpoint, server: true
end

config :msfailab, MsfailabWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("MSFAILAB_PORT", "4000"))]

# Docker configuration from environment variables
# MSFAILAB_DOCKER_ENDPOINT: Unix socket path or "tcp://host:port" for remote daemon
# MSFAILAB_DEFAULT_CONSOLE_IMAGE: Container image for Metasploit (default in config.exs)
# MSF_DB_URL: PostgreSQL URL for MSF containers (from container network perspective)
# MSF_RPC_PASS: Password for MSF RPC authentication
if docker_endpoint = System.get_env("MSFAILAB_DOCKER_ENDPOINT") do
  config :msfailab, docker_endpoint: docker_endpoint
end

if docker_image = System.get_env("MSFAILAB_DEFAULT_CONSOLE_IMAGE") do
  config :msfailab, docker_image: docker_image
end

if msf_db_url = System.get_env("MSF_DB_URL") do
  config :msfailab, msf_db_url: msf_db_url
end

if msf_rpc_pass = System.get_env("MSF_RPC_PASS") do
  config :msfailab, msf_rpc_pass: msf_rpc_pass
end

# MSFAILAB_OLLAMA_THINKING: Enable thinking mode for models that support it (qwen3, deepseek, etc.)
# Default: true - thinking blocks will be requested and streamed
# Set to "false" to disable thinking mode
ollama_thinking = System.get_env("MSFAILAB_OLLAMA_THINKING", "true") in ~w(true 1 yes)
config :msfailab, ollama_thinking: ollama_thinking

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :msfailab, Msfailab.Repo,
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
    System.get_env("MSFAILAB_SECRET_KEY_BASE") ||
      raise """
      environment variable MSFAILAB_SECRET_KEY_BASE is missing.
      Generate one with: openssl rand -base64 48
      """

  # Public hostname for URL generation (WebSocket endpoints, redirects, etc.)
  host = System.get_env("MSFAILAB_HOST", "localhost")
  port = String.to_integer(System.get_env("MSFAILAB_PORT", "4000"))

  config :msfailab, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :msfailab, MsfailabWeb.Endpoint,
    url: [host: host, port: port, scheme: "http"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :msfailab, MsfailabWeb.Endpoint,
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
  #     config :msfailab, MsfailabWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :msfailab, Msfailab.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
