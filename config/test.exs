import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :msfailab, Msfailab.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "msfailab_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :msfailab, MsfailabWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Nv3Tu8KZEv3/whURYk8h2GLvjyOC+kWoLzgPIA0U+IkNHamQEJ14xWANoZVR/EFp",
  server: false

# In test we don't send emails
config :msfailab, Msfailab.Mailer, adapter: Swoosh.Adapters.Test

# Use Mox mocks for external adapters in tests
config :msfailab, docker_adapter: Msfailab.Containers.DockerAdapterMock
config :msfailab, msgrpc_client: Msfailab.Containers.Msgrpc.ClientMock

# Don't start container supervision tree automatically in tests - tests manage their own
config :msfailab, start_containers: false

# Don't start LLM supervision tree in tests - tests use mocked providers
config :msfailab, start_llm: false

# LLM HTTP request options - fast timeouts and no retries for tests
config :msfailab, :llm_req_options, receive_timeout: 10, retry: false

# Fast timing values for tests - minimized for fast execution while avoiding race conditions
# Container GenServer timing (production defaults in parentheses)
config :msfailab, :container_timing,
  health_check_interval_ms: 100,
  # (30_000)
  max_restart_count: 5,
  # (5) - keep same
  base_backoff_ms: 10,
  # (1_000)
  max_backoff_ms: 50,
  # (60_000)
  success_reset_ms: 100,
  # (300_000)
  msgrpc_initial_delay_ms: 5,
  # (5_000)
  msgrpc_max_connect_attempts: 10,
  # (10) - keep same for proper testing
  msgrpc_connect_base_backoff_ms: 10,
  # (2_000)
  console_restart_base_backoff_ms: 10,
  # (1_000)
  console_restart_max_backoff_ms: 50,
  # (30_000)
  console_max_restart_attempts: 10

# (10) - keep same

# Console GenServer timing (production defaults in parentheses)
config :msfailab, :console_timing,
  poll_interval_ms: 5,
  # (100)
  max_retries: 3,
  # (3) - keep same
  retry_delays_ms: [5, 10, 20]

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure logging for tests - SilentLogger captures all logs in ETS
# while suppressing console output by default. Use PRINT_LOGS=true to
# enable console output for debugging.
config :logger, level: :debug

# Disable default console handler - SilentLogger handles all test logging
config :logger, :default_handler, false

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
