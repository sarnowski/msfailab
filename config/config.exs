# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :msfailab,
  ecto_repos: [Msfailab.Repo],
  generators: [timestamp_type: :utc_datetime],
  # Docker adapter configuration
  docker_adapter: Msfailab.Containers.DockerAdapter.Api,
  docker_endpoint: "/var/run/docker.sock",
  docker_image: "msfailab-msfconsole",
  docker_network: "msfailab",
  # MSF RPC configuration
  msf_rpc_port: 55_553,
  msf_rpc_pass: "secret",
  # Database URL for MSF containers (from container's network perspective)
  msf_db_url: "postgres://postgres:postgres@msfailab-postgres:5432/msfailab_dev"

# Configure the endpoint
config :msfailab, MsfailabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MsfailabWeb.ErrorHTML, json: MsfailabWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Msfailab.PubSub,
  live_view: [signing_salt: "HgiiJ5KN"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :msfailab, Msfailab.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  msfailab: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  msfailab: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    # Process-level context
    :workspace_id,
    :container_id,
    :container_name,
    :track_id,
    # Per-message metadata
    :reason,
    :console_id,
    :docker_container_id,
    :docker_name,
    :name,
    :image,
    :network,
    :rpc_host,
    :rpc_port,
    :attempt,
    :attempts,
    :max_attempts,
    :max_retries,
    :backoff_ms,
    :restart_count,
    :registered,
    :started_count,
    :count,
    :exit_code,
    :status,
    :body,
    :labels,
    :command,
    :url,
    :method,
    :container_record_id,
    :history_blocks,
    :pending_tools,
    :error,
    # LLM-related metadata
    :provider,
    :providers,
    :model_count,
    :model_names,
    :default_model,
    :requested,
    :available,
    :context_window,
    # Chat streaming metadata
    :model,
    :index,
    :type,
    :stop_reason,
    :input_tokens,
    :output_tokens,
    :recoverable,
    :chat_entries,
    # Bash command metadata
    :command_id,
    :output_bytes
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
